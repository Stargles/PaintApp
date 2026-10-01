import XCTest
import SwiftUI
import UIKit

/// **TODO (129) and (128) — Add → Rectangle, Ellipse and Linear Gradient as objects of the fill
/// tool's own kind.** `CanvasManager+FillObjects.swift` lays each down as a `VectorFillElement`
/// (a flat or gradient `FillPaint`), and every assertion about *drawn* content here reads pixels —
/// `PixelOps.rasterize` for the cel, `Compositor.composite` for the frame — rather than the stored
/// field, because the stored field is exactly what a render path that never read it would leave
/// correct. `FillObjectUITests` drives the same features from a fresh document through the menu.
///
/// `@MainActor` because `makeRenderRequest` and `makeFrameRecipe` are.
@MainActor
final class FillObjectLogicTests: XCTestCase {

    private var side: Int { Int(CanvasFixture.canvasSize.width) }

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A manager with a raster layer at 0 and an **active vector layer at 1**.
    private func vectorFixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    /// The active cel flattened, off the model — what the canvas would show of this layer alone.
    private func flattened(_ manager: CanvasManager, layerIndex: Int) -> CGImage? {
        PixelOps.rasterize(cel: manager.layers[layerIndex].cels[0],
                           canvasSize: CanvasFixture.canvasSize).cgImage
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    private func steps(_ manager: CanvasManager) -> Int { manager.history.undoStack.count }

    private let red = Color(red: 1, green: 0, blue: 0)

    // MARK: - (129) Rectangle and Ellipse

    /// **The object is the fill tool's own kind, in the brush colour, centred on the artwork.** A
    /// stored-field assertion on purpose — the picture is the next two tests' — because "what kind of
    /// element" is the whole of the ruling: *"make it the same type of shape as what the fill tool
    /// lays down."*
    ///
    /// Mutation caught: laying the rectangle down as anything but a `VectorFillElement` (a stroke, a
    /// smart shape) leaves `fills` empty.
    func testARectangleIsAFillElementOfTheBrushColourCentredOnTheArtwork() throws {
        let (manager, _, vector) = vectorFixture()
        manager.brushColor = red
        XCTAssertTrue(manager.addSolidShape(.rectangle))

        let fill = try XCTUnwrap(vector.elements.compactMap(\.fill).first, "the rectangle is a fill element")
        XCTAssertEqual(vector.elements.count, 1, "…and nothing else was laid down")
        XCTAssertEqual(fill.solidColor, CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                       "the brush colour, as the fill tool paints it")
        let box = try XCTUnwrap(fill.cgPath).boundingBoxOfPath
        let expected = try XCTUnwrap(manager.defaultShapeRect)
        XCTAssertEqual(box.midX, expected.midX, accuracy: 0.01)
        XCTAssertEqual(box.midY, expected.midY, accuracy: 0.01)
        XCTAssertEqual(box.width, 0.6 * CGFloat(side), accuracy: 0.01,
                       "60% of the artwork's shorter side")
        XCTAssertEqual(box.width, box.height, accuracy: 0.01, "a square")
    }

    /// **Solid means every pixel inside is the colour, and the ellipse is an ellipse.** The rectangle's
    /// corner pixel is inked; the ellipse's is not, while the centre of both is.
    ///
    /// Mutation caught: swapping `.ellipse`'s path for the rectangle's inks the ellipse's corner.
    func testARectangleAndAnEllipseAreSolidAndTheEllipseLeavesItsCorners() throws {
        let rect = vectorFixture()
        rect.manager.brushColor = red
        rect.manager.addSolidShape(.rectangle)
        rect.manager.commitAllInteractiveState()   // settle the Move box the shape arrives held in
        let rectImage = try XCTUnwrap(flattened(rect.manager, layerIndex: rect.layerIndex))
        let ellipse = vectorFixture()
        ellipse.manager.brushColor = red
        ellipse.manager.addSolidShape(.ellipse)
        ellipse.manager.commitAllInteractiveState()
        let ellipseImage = try XCTUnwrap(flattened(ellipse.manager, layerIndex: ellipse.layerIndex))

        // The shape spans 12.8…51.2; (16, 16) is inside the square and outside the circle.
        XCTAssertEqual(pixel(rectImage, 32, 32), [255, 0, 0, 255], "the rectangle is solid at its centre")
        XCTAssertEqual(pixel(rectImage, 16, 16), [255, 0, 0, 255], "…and at its corner")
        XCTAssertEqual(pixel(ellipseImage, 32, 32), [255, 0, 0, 255], "the ellipse is solid at its centre")
        XCTAssertEqual(pixel(ellipseImage, 16, 16)[3], 0, "…and leaves the corner of its bounding box bare")
        XCTAssertEqual(pixel(rectImage, 4, 4)[3], 0, "nothing outside the shape is inked")
    }

    /// **On a vector layer the shape arrives held in the Move box, so it can be sized at once**, and
    /// the box is around the shape alone — not the layer's other ink.
    func testAShapeOnAVectorLayerIsHeldInTheMoveBoxAroundItAlone() throws {
        let (manager, _, vector) = vectorFixture()
        let before = VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 3, opacity: 1,
                                  samples: [VectorSample(x: 2, y: 2, pressure: 1), VectorSample(x: 8, y: 2, pressure: 1)],
                                  composite: .paint)
        vector.addStroke(before)
        manager.addSolidShape(.rectangle)

        let float = try XCTUnwrap(manager.vectorFloat, "the Move box is up")
        let shapeID = try XCTUnwrap(vector.elements.compactMap(\.fill).first?.id)
        XCTAssertEqual(float.parts.flatMap { $0.insideIDs }, [shapeID],
                       "the box carries the new shape and no other element")
    }

    /// **A raster layer gets pixels through the fill tool's raster arm, and no box.** There is no
    /// element to lift, so the tier's own limit shows: the shape lands, and sizing it is Move's
    /// lasso route.
    func testAShapeOnARasterLayerIsPaintedIntoTheCelWithNoMoveBox() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.brushColor = red
        let baseline = steps(manager)
        XCTAssertTrue(manager.addSolidShape(.rectangle))

        XCTAssertNil(manager.vectorFloat, "a raster shape raises no Move box")
        XCTAssertEqual(manager.layers.count, 1, "and needs no new layer")
        let image = try XCTUnwrap(flattened(manager, layerIndex: 0))
        XCTAssertEqual(pixel(image, 32, 32), [255, 0, 0, 255], "the pixels are in the cel")
        XCTAssertEqual(pixel(image, 4, 4)[3], 0, "and only inside the shape")
        XCTAssertEqual(steps(manager) - baseline, 1, "one undo step")
    }

    /// **A layer with no drawing surface gets a vector layer to put the shape on**, the way an
    /// imported photo does, instead of an Add row that silently does nothing there.
    func testAShapeOnAValueLayerLandsOnAFreshVectorLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        XCTAssertEqual(manager.activeLayerKind, .value, "PREMISE: the active layer has no drawing surface")
        let layerCount = manager.layers.count

        XCTAssertTrue(manager.addSolidShape(.ellipse))

        XCTAssertEqual(manager.layers.count, layerCount + 1)
        XCTAssertEqual(manager.activeLayerKind, .vector)
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels.first?.vector)
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1, "the shape is on it")
    }

    /// **The default rectangle is the artwork's, not the buffer's**: with padding the paper is inset,
    /// and centring on `origin: .zero, size: artworkSize` was off by the padding on both axes.
    func testTheDefaultShapeIsCentredOnTheArtworkRectWhenThereIsPadding() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasPadding = 8
        let artwork = try XCTUnwrap(manager.artworkRect)
        XCTAssertEqual(artwork, CGRect(x: 8, y: 8, width: 48, height: 48))
        let shape = try XCTUnwrap(manager.defaultShapeRect)
        XCTAssertEqual(shape.midX, 32, accuracy: 0.001)
        XCTAssertEqual(shape.midY, 32, accuracy: 0.001)
        XCTAssertEqual(shape.width, 28.8, accuracy: 0.001, "60% of the artwork's 48, not of the buffer's 64")
    }

    /// One undo step takes the shape away, and a redo puts it back.
    func testAShapeIsOneUndoStep() throws {
        let (manager, _, vector) = vectorFixture()
        manager.addSolidShape(.rectangle)
        manager.commitAllInteractiveState()
        let baseline = steps(manager)
        manager.undo()
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 0, "undo takes the shape away")
        XCTAssertEqual(baseline - steps(manager), 1)
        manager.redo()
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1, "and redo puts it back")
    }

    /// **The Select panel's Fill goes through the same add path** (`layDownSolidFill`), so "Fill"
    /// means one thing whichever door it arrives from.
    func testFillOnASelectionLaysDownAFillElementThroughTheSharedPath() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        manager.brushColor = red
        let loop = CGPath(rect: CGRect(x: 10, y: 10, width: 20, height: 20), transform: nil)
        manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
        let baseline = steps(manager)
        manager.fillSelection()
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1)
        XCTAssertEqual(steps(manager) - baseline, 1)
    }

    // MARK: - (128) The gradient is an object

    /// **Add → Linear Gradient lays a gradient fill over the artwork and the pixels ramp along its
    /// axis** — black at the left edge, white at the right, mid-grey between, and constant down any
    /// column. The two-operands trap applied: a fixture that checked `paint` would stay green against
    /// a draw path that never read it.
    ///
    /// Mutation caught: drawing `.linearGradient` with the solid arm's fill leaves every pixel one
    /// colour and the ramp assertions go red.
    func testALinearGradientRampsAcrossTheArtworkAndIsConstantDownAColumn() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        XCTAssertTrue(manager.addGradient())
        manager.commitAllInteractiveState()

        XCTAssertEqual(vector.elements.compactMap(\.fill).compactMap(\.gradient).count, 1,
                       "the gradient is an element of the vector layer")
        let image = try XCTUnwrap(flattened(manager, layerIndex: layerIndex))
        let left = pixel(image, 0, 32), middle = pixel(image, side / 2, 32), right = pixel(image, side - 1, 32)
        XCTAssertLessThan(left[0], 12, "black at the left edge")
        XCTAssertGreaterThan(right[0], 243, "white at the right edge")
        XCTAssertEqual(middle[0], 128, accuracy: 6, "the middle is the mean — a ramp, not a step")
        XCTAssertEqual(left[3], 255); XCTAssertEqual(right[3], 255)
        for y in [2, 32, 61] {
            XCTAssertEqual(pixel(image, 20, y), pixel(image, 20, 32),
                           "a left-to-right ramp is constant down a column (y = \(y))")
        }
        var last = -1
        for x in stride(from: 0, to: side, by: 4) {
            let value = pixel(image, x, 32)[0]
            XCTAssertGreaterThanOrEqual(value, last, "the ramp never goes backwards (x = \(x))")
            last = value
        }
    }

    /// **The panel's angle turns the ramp, live, and the whole session is one undo step.** 90 degrees
    /// runs top to bottom: the rows now differ and a row is constant. Undo returns to the
    /// left-to-right gradient exactly.
    func testTurningTheAngleRunsTheRampDownTheCanvasAsOneUndoStep() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        manager.addGradient()
        let baseline = steps(manager)
        let original = try XCTUnwrap(manager.editedGradient)

        manager.setGradientAngle(.pi / 2)
        manager.setGradientAngle(.pi / 2)   // a second write of the same value changes nothing
        let image = try XCTUnwrap(flattened(manager, layerIndex: layerIndex))
        XCTAssertLessThan(pixel(image, 32, 0)[0], 12, "black at the top")
        XCTAssertGreaterThan(pixel(image, 32, side - 1)[0], 243, "white at the bottom")
        XCTAssertEqual(pixel(image, 4, 20), pixel(image, 60, 20), "constant along a row")
        XCTAssertEqual(try XCTUnwrap(manager.editedGradient).angle, .pi / 2, accuracy: 1e-6)

        XCTAssertTrue(manager.commitGradientEdit())
        XCTAssertNil(manager.gradientEdit, "the session is closed")
        XCTAssertEqual(steps(manager) - baseline, 1, "one step for the whole session")

        manager.undo()
        XCTAssertEqual(vector.elements.compactMap(\.fill).first?.gradient, original,
                       "undo restores the paint exactly")
        manager.redo()
        XCTAssertEqual(try XCTUnwrap(vector.elements.compactMap(\.fill).first?.gradient).angle,
                       .pi / 2, accuracy: 1e-6, "and redo re-applies it")
    }

    /// The two swatches write their own end, alpha included, and a panel opened and closed untouched
    /// records nothing.
    func testTheSwatchesWriteTheirOwnEndAndAnUntouchedPanelRecordsNothing() throws {
        let (manager, _, _) = vectorFixture()
        manager.addGradient()
        let baseline = steps(manager)
        XCTAssertFalse(manager.commitGradientEdit(), "nothing was changed")
        XCTAssertEqual(steps(manager), baseline, "…so no step")

        let id = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector?.elements.first?.id)
        XCTAssertTrue(manager.beginGradientEdit(elementID: id), "the gradient can be reopened by id")
        manager.setGradientColour(.start, to: Color(red: 1, green: 0, blue: 0, opacity: 0.5))
        manager.setGradientColour(.end, to: Color(red: 0, green: 0, blue: 1))
        let edited = try XCTUnwrap(manager.editedGradient)
        XCTAssertEqual(edited.start.red, 1, accuracy: 0.01)
        XCTAssertEqual(edited.start.alpha, 0.5, accuracy: 0.01, "a gradient to transparent is allowed")
        XCTAssertEqual(edited.end.blue, 1, accuracy: 0.01)
        XCTAssertEqual(edited.end.red, 0, accuracy: 0.01, "the end was not touched by the start's write")
        XCTAssertTrue(manager.commitGradientEdit())
        XCTAssertEqual(steps(manager) - baseline, 1)
    }

    /// **An edit made to the gradient has to move the keys the caches use.** The vector tier's
    /// `committedVersion` is part of `LayerContentVersion`, and `FrameBakeKey` digests that version —
    /// so a recoloured gradient names a different frame on disk. Without this a baked frame would be
    /// served with the old colours.
    func testEditingAGradientMovesTheLayerContentVersionAndTheBakeKey() throws {
        let (manager, layerIndex, _) = vectorFixture()
        manager.addGradient()
        manager.commitAllInteractiveState()
        let id = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector?.elements.first?.id)

        func digest() throws -> String {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, quality: .full,
                                                                includeBackground: true, sizing: .native))
            return FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0,
                                backend: .coreGraphics, formatVersion: FrameBakeStore.formatVersion).fileName
        }
        func version() -> LayerContentVersion {
            LayerContentVersion(cel: manager.layers[layerIndex].cels[0])
        }
        let digestBefore = try digest(), versionBefore = version()

        XCTAssertTrue(manager.beginGradientEdit(elementID: id))
        manager.setGradientColour(.end, to: Color(red: 0, green: 1, blue: 0))
        manager.commitGradientEdit()

        XCTAssertNotEqual(version(), versionBefore, "the cel's content version moved")
        XCTAssertNotEqual(try digest(), digestBefore, "…and so did the frame's name on disk")
    }

    /// **Both compositors draw a gradient object identically**, by construction — the gradient is
    /// rasterised once into the cel's picture and both backends composite those same pixels — and
    /// pinned here rather than assumed, with a translucent end so the premultiply is exercised too.
    /// The pattern is `CompositorParityLogicTests`': byte for byte, skipped without a Metal device.
    func testBothCompositorsDrawAGradientObjectByteForByte() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
        let (manager, _, _) = vectorFixture()
        manager.addGradient()
        manager.setGradientColour(.start, to: Color(red: 0.9, green: 0.2, blue: 0.1))
        manager.setGradientColour(.end, to: Color(red: 0.1, green: 0.3, blue: 0.9, opacity: 0.5))
        manager.setGradientAngle(.pi / 6)
        manager.commitAllInteractiveState()

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("the fixture must produce a render request")
        }
        Compositor.backend = .coreGraphics
        let cpu = try XCTUnwrap(Compositor.composite(request), "the CoreGraphics composite")
        Compositor.backend = .metal
        let gpu = try XCTUnwrap(Compositor.composite(request), "the Metal composite")
        let a = try XCTUnwrap(CanvasFixture.rgbaBytes(cpu)), b = try XCTUnwrap(CanvasFixture.rgbaBytes(gpu))
        XCTAssertEqual(a.count, b.count)
        var worst = 0
        for i in 0..<min(a.count, b.count) { worst = max(worst, abs(Int(a[i]) - Int(b[i]))) }
        XCTAssertEqual(worst, 0, "the two backends differ by up to \(worst)/255 on a gradient object")
        XCTAssertTrue(a.contains { $0 != 0 }, "PREMISE: the composite is not blank")
    }

    // MARK: - The paint travels with the element

    /// **A gradient fill is carried by every transform a fill is** — Move's affine and a Distort's
    /// homography — and its two points follow its path. A Move of (+10, +5) puts each point at its
    /// own place + (10, 5); a cut piece keeps the parent's points.
    func testTheGradientsPointsFollowTheFillThroughMoveAndCutAndKeepTheirIdentity() throws {
        let gradient = LinearGradientPaint(start: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                           end: CodableColor(red: 1, green: 1, blue: 1, alpha: 1),
                                           from: CGPoint(x: 10, y: 20), to: CGPoint(x: 50, y: 20))
        var fill = VectorFillElement(path: CGPath(rect: CGRect(x: 10, y: 10, width: 40, height: 20), transform: nil),
                                     paint: .linearGradient(gradient), opacity: 0.8)
        fill.animationGroupID = UUID()

        // Move: an affine through the one function a lasso nudge uses.
        let moved = VectorCanvas.mapping(.fill(fill), throughSimilarity: CGAffineTransform(translationX: 10, y: 5))
        let movedFill = try XCTUnwrap(moved.fill)
        XCTAssertEqual(movedFill.gradient?.from, CGPoint(x: 20, y: 25))
        XCTAssertEqual(movedFill.gradient?.to, CGPoint(x: 60, y: 25))
        XCTAssertEqual(movedFill.id, fill.id, "a nudge moves an element, it does not mint one")
        XCTAssertEqual(movedFill.animationGroupID, fill.animationGroupID)
        XCTAssertEqual(movedFill.opacity, 0.8)
        XCTAssertEqual(try XCTUnwrap(movedFill.cgPath).boundingBoxOfPath.minX, 20, accuracy: 0.01,
                       "the path moved with it")

        // Distort: a homography (here a pure translation, so the arithmetic is checkable).
        let translated = Homography.translation(x: 3, y: -4)
        let distorted = try XCTUnwrap(VectorCanvas.mapping(.fill(fill), through: translated)?.fill)
        let from = try XCTUnwrap(distorted.gradient?.from)
        XCTAssertEqual(from.x, 13, accuracy: 1e-6)
        XCTAssertEqual(from.y, 16, accuracy: 1e-6)

        // A cut: the halves are the same picture through smaller windows.
        let halved = fill.reshaped(to: CGPath(rect: CGRect(x: 10, y: 10, width: 20, height: 20), transform: nil))
        XCTAssertEqual(halved.gradient, gradient, "a cut half keeps the parent's points")
        XCTAssertEqual(halved.opacity, fill.opacity)
    }

    /// **A lasso Move of a gradient is a real Move**: lifted by the lasso, nudged, baked — and the
    /// ramp is where the fill went, not left behind at the old coordinates.
    func testAMovedGradientFillRampsWhereItWentNotWhereItWas() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let rect = CGRect(x: 0, y: 0, width: 32, height: 64)
        vector.addFill(canvasSpacePath: CGPath(rect: rect, transform: nil),
                       paint: .linearGradient(.spanning(rect, angle: 0)))
        let id = try XCTUnwrap(vector.elements.first?.id)
        XCTAssertTrue(manager.beginVectorMove(ofElementIDs: [id]))
        var frame = try XCTUnwrap(manager.vectorFloat).frame.transform
        frame.position.x += 32
        manager.nudgeVectorFloat(to: frame)
        manager.commitAllInteractiveState()

        let image = try XCTUnwrap(flattened(manager, layerIndex: layerIndex))
        XCTAssertEqual(pixel(image, 8, 32)[3], 0, "nothing is left at the old position")
        let near = pixel(image, 33, 32), far = pixel(image, 62, 32)
        XCTAssertLessThan(near[0], 20, "black at the moved fill's left edge")
        XCTAssertGreaterThan(far[0], 235, "white at its right edge")
    }

    // MARK: - The document format

    /// **A flat fill's payload is what it always was, a gradient writes `gradient` and no `color`, and
    /// a document written before gradients decodes unchanged.**
    func testTheDocumentFormatKeepsAFlatFillByteForByteAndRoundTripsAGradient() throws {
        let path = CGPath(rect: CGRect(x: 1, y: 2, width: 10, height: 10), transform: nil)
        let flat = VectorFillElement(path: path, color: CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        let flatJSON = try XCTUnwrap(String(data: JSONEncoder().encode(flat), encoding: .utf8))
        XCTAssertTrue(flatJSON.contains("\"color\""), "a flat fill still writes `color`")
        XCTAssertFalse(flatJSON.contains("\"gradient\""), "…and no gradient key")

        let ramp = VectorFillElement(path: path, paint: .linearGradient(.spanning(CGRect(x: 0, y: 0, width: 8, height: 4),
                                                                                  angle: 0.4)))
        let rampData = try JSONEncoder().encode(ramp)
        let rampJSON = try XCTUnwrap(String(data: rampData, encoding: .utf8))
        XCTAssertTrue(rampJSON.contains("\"gradient\""))
        XCTAssertFalse(rampJSON.contains("\"color\""), "a gradient is not also a flat colour")
        let decoded = try JSONDecoder().decode(VectorFillElement.self, from: rampData)
        XCTAssertEqual(decoded.paint, ramp.paint, "the gradient round-trips")
        XCTAssertEqual(decoded.id, ramp.id)
        XCTAssertNotNil(decoded.cgPath)

        // A document written before gradients existed: the same keys as today's flat payload.
        let legacy = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(flat)) as? [String: Any])
        XCTAssertEqual(Set(legacy.keys), ["id", "pathData", "color", "opacity", "evenOddFill"],
                       "the flat payload's keys are the legacy ones")
        let restored = try JSONDecoder().decode(VectorFillElement.self,
                                                from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.solidColor, flat.solidColor)
    }

    // MARK: - Reached only where it should be

    /// **Change Colour does not flatten a gradient**, and Opacity reaches it like any fill.
    func testChangeColourSkipsAGradientAndOpacityReachesIt() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let rect = CGRect(x: 10, y: 10, width: 40, height: 40)
        vector.addFill(canvasSpacePath: CGPath(rect: rect, transform: nil),
                       paint: .linearGradient(.spanning(rect, angle: 0)))
        let before = try XCTUnwrap(vector.elements.first?.fill?.paint)
        let loop = CGPath(rect: CGRect(x: 2, y: 2, width: 60, height: 60), transform: nil)
        manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)

        XCTAssertFalse(manager.applySelectionEdit(.color(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))),
                       "a hue written over both ends would flatten it, so Colour does not reach it")
        XCTAssertEqual(vector.elements.first?.fill?.paint, before)
        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.4)), "Opacity does")
        XCTAssertEqual(vector.elements.first?.fill?.opacity, 0.4)
    }
}
