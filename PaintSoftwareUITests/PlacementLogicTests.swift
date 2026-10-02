import XCTest
import SwiftUI
import UIKit

/// **TODO (149) — Add-menu objects are primed, then dragged out with the pen.** The model of it:
/// the geometry a drag makes of a press and a pen (`ShapeGeometry.dragged`, `.band`), the priming
/// lifecycle (`CanvasManager.primeObject` … `leavePlacement`, and every way a tool switch ends it), and
/// the one-lift-one-undo-step placement of each kind of object. `FillObjectUITests` drives the same
/// features from a fresh document through the menu and the canvas.
///
/// Every assertion about where something *lands* reads what the document holds after the lift, not what
/// a preview was told — the preview is `PlacementPlan`, the same value the lift lays down, so a test of
/// the plan alone would be testing a definition.
@MainActor
final class PlacementLogicTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("placement-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VideoImportStore.directoryOverride = directory.appendingPathComponent("staged", isDirectory: true)
    }

    override func tearDownWithError() throws {
        VideoImportStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Fixtures

    /// A manager with a raster layer at 0 and an **active vector layer at 1**.
    private func vectorFixture() -> (manager: CanvasManager, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        guard let vector = manager.layers[manager.currentLayerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, vector)
    }

    private func steps(_ manager: CanvasManager) -> Int { manager.history.undoStack.count }

    private func solidPicture(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func clip(named name: String = "clip") throws -> URL {
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).mp4")
        try CanvasFixture.writeGreyClip(levels: [40, 110], fps: 24, side: 32, to: url)
        return url
    }

    private func pen(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    // MARK: - The geometry of a drag

    /// **The pen is always on the outline of a dragged rectangle, and the rectangle is upright and
    /// centred on the press** — whichever quadrant the pen goes to, and however it turns around the
    /// press. Mutation caught: anchoring the box at a corner (centre off the press), reading only one
    /// axis, or leaving a rotation on it.
    func testADraggedRectangleIsUprightCentredOnThePressWithThePenOnItsEdge() {
        let anchor = pen(30, 20)
        for offset in [pen(10, 3), pen(-10, 3), pen(-4, -12), pen(2, 9), pen(0, -7)] {
            let tip = pen(anchor.x + offset.x, anchor.y + offset.y)
            let shape = ShapeGeometry.dragged(.rectangle, from: anchor, to: tip)
            XCTAssertEqual(shape.kind, .rectangle)
            XCTAssertEqual(shape.rotation, 0, "rotation is locked — dragging only sizes it")
            XCTAssertEqual(shape.center.x, anchor.x, accuracy: 1e-9, "centred on the press, offset \(offset)")
            XCTAssertEqual(shape.center.y, anchor.y, accuracy: 1e-9)
            let box = shape.boundingRect
            XCTAssertEqual(box.width, box.height, accuracy: 1e-9, "a square")
            XCTAssertEqual(max(abs(tip.x - box.midX) - box.width / 2, abs(tip.y - box.midY) - box.height / 2), 0,
                           accuracy: 1e-9, "the pen is on its edge, offset \(offset)")
        }
    }

    /// **A dragged circle's edge passes through the pen**, so it grows with the pen and does not lag it
    /// on a diagonal the way the two-finger constraint's `max(width, height)` circle would. Mutation
    /// caught: sizing it by the larger axis (the pen sits outside the circle at 45 degrees).
    func testADraggedCircleRidesThePensDistanceFromThePress() {
        let anchor = pen(32, 32)
        for offset in [pen(12, 0), pen(0, -9), pen(6, 6), pen(-8, 15)] {
            let tip = pen(anchor.x + offset.x, anchor.y + offset.y)
            let shape = ShapeGeometry.dragged(.oval, from: anchor, to: tip)
            let box = shape.boundingRect
            XCTAssertEqual(shape.kind, .oval)
            XCTAssertEqual(box.width, box.height, accuracy: 1e-9, "a circle")
            XCTAssertEqual(box.width / 2, hypot(offset.x, offset.y), accuracy: 1e-9,
                           "its radius is the pen's distance from the press, offset \(offset)")
            XCTAssertEqual(shape.center.x, anchor.x, accuracy: 1e-9)
            XCTAssertEqual(shape.center.y, anchor.y, accuracy: 1e-9)
        }
    }

    /// **A picture keeps its own shape**: the box has the picture's aspect ratio and the pen on its
    /// outline, so a square would not be what a wide picture is dragged out as.
    func testADraggedPictureKeepsItsAspectRatioWithThePenOnItsEdge() {
        let anchor = pen(40, 40)
        for (aspect, offset) in [(CGFloat(4), pen(20, 3)), (4, pen(2, 9)), (0.5, pen(6, 6)), (1.5, pen(-9, 4))] {
            let tip = pen(anchor.x + offset.x, anchor.y + offset.y)
            let box = ShapeGeometry.dragged(.rectangle, from: anchor, to: tip, aspect: aspect).boundingRect
            XCTAssertEqual(box.width / box.height, aspect, accuracy: 1e-9, "aspect \(aspect), offset \(offset)")
            XCTAssertEqual(box.midX, anchor.x, accuracy: 1e-9)
            XCTAssertEqual(box.midY, anchor.y, accuracy: 1e-9)
            XCTAssertEqual(max(abs(tip.x - box.midX) - box.width / 2, abs(tip.y - box.midY) - box.height / 2), 0,
                           accuracy: 1e-9, "the pen is on its edge, aspect \(aspect), offset \(offset)")
        }
    }

    /// **A gradient's band is the line's own length and the asked width, turned along the line.** Its
    /// corners projected onto the line's direction run from the press to the pen exactly, and across it
    /// from minus to plus half the width. Mutation caught: dropping the rotation (the band stays
    /// horizontal), or taking the width from the wrong axis.
    func testAGradientBandSpansTheLineAtTheAskedWidthWhateverItsDirection() throws {
        for (from, to) in [(pen(10, 10), pen(40, 50)), (pen(50, 40), pen(8, 12)), (pen(5, 30), pen(55, 30))] {
            let line = ShapeGeometry.dragged(.line, from: from, to: to)
            let band = line.band(width: 12)
            let length = hypot(to.x - from.x, to.y - from.y)
            let axis = pen((to.x - from.x) / length, (to.y - from.y) / length)
            let across = pen(-axis.y, axis.x)
            var corners: [CGPoint] = []
            band.rotatedCGPath.applyWithBlock { element in
                if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                    corners.append(element.pointee.points[0])
                }
            }
            XCTAssertGreaterThanOrEqual(corners.count, 4, "the band is a rectangle")
            let along = corners.map { ($0.x - from.x) * axis.x + ($0.y - from.y) * axis.y }
            let sideways = corners.map { ($0.x - from.x) * across.x + ($0.y - from.y) * across.y }
            XCTAssertEqual(along.min() ?? .nan, 0, accuracy: 1e-6, "starts at the press, \(from) → \(to)")
            XCTAssertEqual(along.max() ?? .nan, length, accuracy: 1e-6, "ends at the pen, \(from) → \(to)")
            XCTAssertEqual(sideways.min() ?? .nan, -6, accuracy: 1e-6, "half the width to one side")
            XCTAssertEqual(sideways.max() ?? .nan, 6, accuracy: 1e-6, "half to the other")
        }
    }

    // MARK: - Priming

    func testPrimingSelectsThePlacementToolAndRemembersTheToolBefore() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .pencil
        manager.primeObject(.rectangle)

        XCTAssertEqual(manager.selectedTool, .place)
        XCTAssertEqual(manager.primedObject, .rectangle)
        manager.primeObject(.gradient)
        XCTAssertEqual(manager.primedObject, .gradient, "priming another object replaces the first")
        manager.leavePlacement()
        XCTAssertEqual(manager.selectedTool, .pencil, "the tool the artist had is back — the original, not the placement")
        XCTAssertNil(manager.primedObject)
    }

    func testTappingThePrimedObjectAgainPutsItDownAndTappingAnotherSwitchesIt() {
        let manager = CanvasFixture.manager()
        manager.togglePrimedObject(.ellipse)
        XCTAssertEqual(manager.primedObject, .ellipse)
        manager.togglePrimedObject(.rectangle)
        XCTAssertEqual(manager.primedObject, .rectangle, "another entry replaces it")
        manager.togglePrimedObject(.rectangle)
        XCTAssertNil(manager.primedObject, "the primed entry again puts it down")
        XCTAssertEqual(manager.selectedTool, .pen, "and the brush is back")
    }

    /// **Any other tool taking over ends the priming, with no door having to remember to**, and with it
    /// the memory of what to hand back to.
    func testPickingAnyOtherToolEndsThePriming() {
        for other in Tool.allCases where other != .place && other != .eyedropper {
            let manager = CanvasFixture.manager()
            manager.primeObject(.ellipse)
            manager.selectedTool = other
            XCTAssertNil(manager.primedObject, "\(other) ended the priming")
            XCTAssertNil(manager.toolBeforePlacement, "…and its memory")
        }
    }

    /// **The eyedropper armed over a primed object hands back to it**, so picking a colour for the
    /// shape costs no second trip to the Add menu; and a tool picked while the eyedropper is up ends it.
    func testTheEyedropperArmedOverAPrimedObjectHandsBackToItAndAnotherToolStillEndsIt() {
        let manager = CanvasFixture.manager()
        manager.primeObject(.rectangle)
        manager.selectEyedropper()
        XCTAssertEqual(manager.primedObject, .rectangle, "the pick has not ended the priming")
        manager.leaveEyedropper()
        XCTAssertEqual(manager.selectedTool, .place, "the pick hands back to the primed object")
        XCTAssertEqual(manager.primedObject, .rectangle)

        manager.selectEyedropper()
        manager.selectedTool = .pen   // the artist taps the brush while the eyedropper is armed
        XCTAssertNil(manager.primedObject, "a tool picked over the eyedropper ends the priming it was parked behind")
    }

    /// An armed eyedropper is a momentary tool, and priming is the artist's newer word: it is stood down,
    /// so the placement hands back to the tool *before* the pick and not to a pick that already stopped.
    func testPrimingStandsDownAnArmedEyedropper() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .pencil
        manager.selectEyedropper()
        manager.primeObject(.ellipse)
        XCTAssertEqual(manager.selectedTool, .place)
        manager.leavePlacement()
        XCTAssertEqual(manager.selectedTool, .pencil)
    }

    func testNothingIsPrimedOnADocumentWithNoCanvas() {
        let manager = CanvasManager()
        manager.primeObject(.rectangle)
        XCTAssertNil(manager.primedObject)
        XCTAssertEqual(manager.selectedTool, .pen)
    }

    /// Priming settles what was pending, as any tool switch does: a gradient's open panel is one undo
    /// step, committed before the next edit begins rather than swept out by it.
    func testPrimingSettlesAnOpenGradientSession() {
        let (manager, _) = vectorFixture()
        XCTAssertTrue(manager.dragOut(.gradient, from: pen(8, 32), to: pen(56, 32)))
        XCTAssertNotNil(manager.gradientEdit, "PREMISE: the gradient's panel session is open")
        manager.primeObject(.rectangle)
        XCTAssertNil(manager.gradientEdit, "priming settled it")
    }

    // MARK: - The drag

    /// **One lift, one undo step, the tool handed back, no Move box** — and the shape is where the pen
    /// said: centred on the press, its edge through the lift.
    func testALiftPlacesTheObjectAsOneUndoStepAndHandsTheToolBack() throws {
        let (manager, vector) = vectorFixture()
        manager.selectedTool = .pencil
        let baseline = steps(manager)

        manager.primeObject(.rectangle)
        XCTAssertTrue(manager.beginPlacement(at: pen(32, 32)))
        manager.updatePlacement(to: pen(40, 36))
        XCTAssertEqual(steps(manager), baseline, "nothing touches the document before the lift")
        XCTAssertTrue(vector.elements.isEmpty)
        XCTAssertTrue(manager.endPlacement())

        XCTAssertEqual(steps(manager) - baseline, 1, "one undo step")
        let box = try XCTUnwrap(vector.elements.compactMap(\.fill).first?.cgPath).boundingBoxOfPath
        XCTAssertEqual(box.midX, 32, accuracy: 0.01)
        XCTAssertEqual(box.midY, 32, accuracy: 0.01)
        XCTAssertEqual(box.width, 16, accuracy: 0.01, "twice the larger of the pen's two travels")
        XCTAssertNil(manager.vectorFloat, "no Move box is raised")
        XCTAssertEqual(manager.selectedTool, .pencil, "the tool the artist had is back")
        XCTAssertNil(manager.primedObject)
        XCTAssertNil(manager.placementDrag)

        manager.undo()
        XCTAssertTrue(vector.elements.isEmpty, "one undo took it away")
    }

    /// **A press that never travelled places nothing and leaves the object primed**, so a stray touch
    /// costs the artist nothing. Mutation caught: dropping the travel threshold places a zero-size shape.
    func testADragTooShortToBeAPlacementLeavesTheObjectPrimed() {
        let (manager, vector) = vectorFixture()
        let baseline = steps(manager)
        manager.primeObject(.ellipse)
        XCTAssertTrue(manager.beginPlacement(at: pen(20, 20)))
        manager.updatePlacement(to: pen(21, 21))

        XCTAssertFalse(manager.endPlacement())

        XCTAssertEqual(manager.primedObject, .ellipse, "still primed")
        XCTAssertEqual(manager.selectedTool, .place)
        XCTAssertEqual(steps(manager), baseline, "no undo step")
        XCTAssertTrue(vector.elements.isEmpty)
        XCTAssertNil(manager.placementDrag)
    }

    /// A cancelled touch — a second finger arrived, the system took it — leaves nothing behind.
    func testACancelledTouchLeavesNoTraceAndTheObjectStaysPrimed() {
        let (manager, vector) = vectorFixture()
        let baseline = steps(manager)
        manager.primeObject(.rectangle)
        XCTAssertTrue(manager.beginPlacement(at: pen(20, 20)))
        manager.updatePlacement(to: pen(50, 50))
        XCTAssertNotNil(manager.placementPlan, "the drag is live")

        manager.cancelPlacement()

        XCTAssertNil(manager.placementPlan)
        XCTAssertEqual(manager.primedObject, .rectangle)
        XCTAssertEqual(steps(manager), baseline)
        XCTAssertTrue(vector.elements.isEmpty)
    }

    func testNoPlacementBeginsWithNothingPrimed() {
        let manager = CanvasFixture.manager()
        XCTAssertFalse(manager.beginPlacement(at: pen(10, 10)))
        XCTAssertNil(manager.placementDrag)
        XCTAssertNil(manager.placementPlan)
        XCTAssertFalse(manager.endPlacement())
    }

    /// **The plan the preview draws is the shape the lift lays down.** Mid-drag it is the dragged
    /// geometry; after the lift the stored path's bounds are the same rectangle.
    func testThePlanThePreviewDrawsIsTheShapeTheLiftLaysDown() throws {
        let (manager, vector) = vectorFixture()
        manager.primeObject(.ellipse)
        manager.beginPlacement(at: pen(30, 30))
        manager.updatePlacement(to: pen(30, 44))

        guard case .solid(let planned)? = manager.placementPlan else { return XCTFail("an ellipse plans a solid shape") }
        XCTAssertEqual(planned, ShapeGeometry.dragged(.oval, from: pen(30, 30), to: pen(30, 44)))
        manager.endPlacement()

        let box = try XCTUnwrap(vector.elements.compactMap(\.fill).first?.cgPath).boundingBoxOfPath
        XCTAssertEqual(box.minX, planned.boundingRect.minX, accuracy: 0.01)
        XCTAssertEqual(box.width, planned.boundingRect.width, accuracy: 0.01)
        XCTAssertEqual(box.minY, planned.boundingRect.minY, accuracy: 0.01)
    }

    // MARK: - The gradient

    /// **The Width slider is a share of the artwork's longer side**, so 100% covers the paper whichever
    /// way the gradient is dragged.
    func testAGradientsWidthIsAFractionOfTheArtworksLongerSide() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 64, height: 40)
        manager.gradientWidthFraction = 0.5
        XCTAssertEqual(manager.gradientBandWidth, 32, accuracy: 1e-9, "half of the longer side, 64")
        manager.gradientWidthFraction = 1
        XCTAssertEqual(manager.gradientBandWidth, 64, accuracy: 1e-9)
    }

    /// **The gradient is the band and ends where the pen's line does**: its path is as long as the line
    /// and as wide as the Width asked, its ramp runs press to lift, and the panel opens with it.
    func testAGradientIsTheBandFromThePressToTheLiftAndOpensItsPanel() throws {
        let (manager, vector) = vectorFixture()
        manager.gradientWidthFraction = 0.25   // 16 of the 64-point canvas
        XCTAssertTrue(manager.dragOut(.gradient, from: pen(10, 32), to: pen(50, 32)))

        let fill = try XCTUnwrap(vector.elements.compactMap(\.fill).first)
        let box = try XCTUnwrap(fill.cgPath).boundingBoxOfPath
        XCTAssertEqual(box.minX, 10, accuracy: 0.01, "it starts at the press")
        XCTAssertEqual(box.maxX, 50, accuracy: 0.01, "…and ends at the lift: the length of the line")
        XCTAssertEqual(box.height, 16, accuracy: 0.01, "as wide as the rail's slider says")
        XCTAssertEqual(box.midY, 32, accuracy: 0.01)
        let ramp = try XCTUnwrap(fill.gradient)
        XCTAssertEqual(ramp.from.x, 10, accuracy: 0.01)
        XCTAssertEqual(ramp.to.x, 50, accuracy: 0.01)
        XCTAssertNotNil(manager.gradientEdit, "the panel is open on it")
    }

    /// **A gradient dragged out at an angle is stored turned along the line**, not as the axis-aligned
    /// box the line spans: its stored corners run from the press to the lift along the line and
    /// half the width to either side, and its ramp ends are the press and the lift. Mutation caught:
    /// laying down the band's unrotated path leaves it horizontal whatever way the pen went.
    func testADiagonalGradientIsStoredTurnedAlongTheDrag() throws {
        let (manager, vector) = vectorFixture()
        manager.gradientWidthFraction = 0.25   // 16 points
        let from = pen(10, 10), to = pen(40, 50)
        XCTAssertTrue(manager.dragOut(.gradient, from: from, to: to))

        let fill = try XCTUnwrap(vector.elements.compactMap(\.fill).first)
        let length = hypot(to.x - from.x, to.y - from.y)
        let axis = pen((to.x - from.x) / length, (to.y - from.y) / length)
        var corners: [CGPoint] = []
        try XCTUnwrap(fill.cgPath).applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                corners.append(element.pointee.points[0])
            }
        }
        let along = corners.map { ($0.x - from.x) * axis.x + ($0.y - from.y) * axis.y }
        let sideways = corners.map { ($0.x - from.x) * -axis.y + ($0.y - from.y) * axis.x }
        XCTAssertEqual(along.min() ?? .nan, 0, accuracy: 0.01, "starts at the press")
        XCTAssertEqual(along.max() ?? .nan, length, accuracy: 0.01, "ends at the lift")
        XCTAssertEqual(sideways.min() ?? .nan, -8, accuracy: 0.01)
        XCTAssertEqual(sideways.max() ?? .nan, 8, accuracy: 0.01)
        let ramp = try XCTUnwrap(fill.gradient)
        XCTAssertEqual(ramp.from.x, from.x, accuracy: 0.01)
        XCTAssertEqual(ramp.from.y, from.y, accuracy: 0.01)
        XCTAssertEqual(ramp.to.x, to.x, accuracy: 0.01)
        XCTAssertEqual(ramp.to.y, to.y, accuracy: 0.01)
    }

    /// A gradient is an object in a vector layer and nothing else: dragged out on a raster layer it
    /// gets a layer of its own.
    func testAGradientDraggedOutOnARasterLayerLandsOnAFreshVectorLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let layerCount = manager.layers.count
        XCTAssertTrue(manager.dragOut(.gradient, from: pen(8, 32), to: pen(56, 32)))
        XCTAssertEqual(manager.layers.count, layerCount + 1)
        XCTAssertEqual(manager.activeLayerKind, .vector)
        XCTAssertEqual(try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels.first?.vector)
            .elements.compactMap(\.fill).compactMap(\.gradient).count, 1)
    }

    // MARK: - Pictures

    /// **A placed picture is centred on the press, as wide as the drag made it, and cascades off
    /// nothing** — two dragged out at the same place are in the same place — with no Move box and one
    /// undo step each.
    func testAPlacedPictureIsCentredOnThePressAtTheDraggedWidth() throws {
        let (manager, vector) = vectorFixture()
        let picture = solidPicture(width: 40, height: 10)
        let baseline = steps(manager)

        XCTAssertTrue(manager.primeImage(picture))
        XCTAssertEqual(manager.primedObject?.name, "image")
        manager.beginPlacement(at: pen(30, 30))
        manager.updatePlacement(to: pen(40, 32))   // half height 2.5 at aspect 4 → half width 10
        XCTAssertTrue(manager.endPlacement())

        let element = try XCTUnwrap(vector.elements.compactMap(\.image).first)
        XCTAssertEqual(element.transform.position.x, 30, accuracy: 0.01)
        XCTAssertEqual(element.transform.position.y, 30, accuracy: 0.01)
        XCTAssertEqual(element.transform.scale * 40, 20, accuracy: 0.01, "20 canvas points wide")
        XCTAssertEqual(element.transform.rotation, 0)
        XCTAssertNil(manager.vectorFloat, "no Move box")
        XCTAssertEqual(steps(manager) - baseline, 1)

        XCTAssertTrue(manager.dragOut(.media(PrimedMedia(source: .image(picture), displaySize: picture.size)),
                                      from: pen(30, 30), to: pen(40, 32)))
        let second = try XCTUnwrap(vector.elements.compactMap(\.image).last)
        XCTAssertEqual(second.transform.position.x, 30, accuracy: 0.01, "a second picture at the same place does not cascade")
        XCTAssertEqual(second.transform.position.y, 30, accuracy: 0.01)

        // **A drag that is mostly vertical sizes the picture by its height**, so the pen rides the
        // picture's top or bottom edge and the width is four times the height: a square box would read
        // the same pen as a 10-point picture. Mutation caught: dragging the picture out as a square.
        XCTAssertTrue(manager.dragOut(.media(PrimedMedia(source: .image(picture), displaySize: picture.size)),
                                      from: pen(30, 30), to: pen(32, 35)))
        let tall = try XCTUnwrap(vector.elements.compactMap(\.image).last)
        XCTAssertEqual(tall.transform.scale * 40, 40, accuracy: 0.01,
                       "half the height is the pen's 5 points, so the picture is 10 tall and 40 wide")

        manager.undo()
        XCTAssertEqual(vector.elements.compactMap(\.image).count, 2, "one undo took the third away")
    }

    /// A picture dragged out on a layer that cannot hold it gets a vector layer, as an import does.
    func testAPlacedPictureOnARasterLayerGetsAFreshVectorLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let layerCount = manager.layers.count
        XCTAssertTrue(manager.primeImage(solidPicture(width: 20, height: 20)))
        manager.beginPlacement(at: pen(32, 32))
        manager.updatePlacement(to: pen(44, 32))
        XCTAssertTrue(manager.endPlacement())

        XCTAssertEqual(manager.layers.count, layerCount + 1)
        XCTAssertEqual(manager.activeLayerKind, .vector)
        XCTAssertEqual(try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels.first?.vector).images.count, 1)
    }

    // MARK: - Clips

    /// **A primed clip's file belongs to the primed object**: replaced by another object, put down, or
    /// switched away from, it is deleted — and a clip that will not open is refused with its file left
    /// to the caller.
    func testAPrimedClipsFileIsDeletedWhenThePrimingEndsWithoutAPlacement() throws {
        let manager = CanvasFixture.manager()
        for end in [{ manager.primeObject(.rectangle) }, { manager.leavePlacement() },
                    { manager.selectedTool = .eraser }] as [() -> Void] {
            let url = try clip()
            XCTAssertTrue(manager.primeVideo(at: url))
            XCTAssertEqual(manager.primedObject?.name, "video")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PREMISE: the file is there while primed")
            end()
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the primed clip's file went with it")
            manager.leavePlacement()
        }

        let notAVideo = directory.appendingPathComponent("prose.txt")
        try "not a video".write(to: notAVideo, atomically: true, encoding: .utf8)
        XCTAssertFalse(manager.primeVideo(at: notAVideo), "a file that is not a clip is refused")
        XCTAssertNil(manager.primedObject)
        XCTAssertTrue(FileManager.default.fileExists(atPath: notAVideo.path), "…and left for the caller to clean up")
    }

    /// **A placed clip's file is moved into the document, centred on the press at the dragged width**,
    /// in its own new layer, as one undo step — and nothing is left of the picked file.
    func testAPlacedClipIsMovedIntoTheDocumentAtThePenAndTheTempFileIsGone() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let url = try clip()
        XCTAssertTrue(manager.primeVideo(at: url))
        let baseline = steps(manager)

        manager.beginPlacement(at: pen(32, 32))
        manager.updatePlacement(to: pen(44, 32))   // a square clip, half-extent 12 → 24 across
        XCTAssertTrue(manager.endPlacement())

        let element = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector?.videos.first)
        XCTAssertEqual(element.transform.position.x, 32, accuracy: 0.01)
        XCTAssertEqual(element.transform.position.y, 32, accuracy: 0.01)
        XCTAssertEqual(element.transform.scale * element.naturalSize.width, 24, accuracy: 0.01, "24 canvas points across")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the picked file was moved, not copied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: element.assetURL.path), "…into the document's staging")
        XCTAssertEqual(manager.activeLayerKind, .vector, "in its own new vector layer")
        XCTAssertEqual(steps(manager) - baseline, 2, "the new layer, then the clip — insertVideo's two steps")
        XCTAssertNil(manager.primedObject)
    }
}
