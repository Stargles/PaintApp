import XCTest
import Combine
import SwiftUI
import UIKit

/// **TODO (129) and (128) — Add → Rectangle, Ellipse and Linear Gradient as objects of the fill
/// tool's own kind.** `CanvasManager+FillObjects.swift` lays each down as a `VectorFillElement`
/// (a flat or gradient `FillPaint`) at the geometry the pen dragged out (`CanvasManager.dragOut`, the
/// TODO (149) gesture), and every assertion about *drawn* content here reads pixels —
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
    private func flattened(_ manager: CanvasManager, layerIndex: Int) throws -> CGImage? {
        (try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[layerIndex].cels[0],
                           canvasSize: CanvasFixture.canvasSize))).cgImage
    }

    /// What the gradient panel's window shows now: the live edit's list drawn as a canvas holding it
    /// would draw it. A tick is held off the document (TODO (173)), so mid-session `flattened` still
    /// says what the cel says.
    private func heldFlattened(_ manager: CanvasManager) throws -> CGImage? {
        guard let live = manager.liveCelContentEdit, let vector = live.vectorCanvas else { return nil }
        return (try XCTUnwrap(VectorCanvas(size: vector.size, elements: live.elements).render())).cgImage
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    private func steps(_ manager: CanvasManager) -> Int { manager.history.undoStack.count }

    private let red = Color(red: 1, green: 0, blue: 0)

    /// A square or circle of half-extent 19.2 centred on the 64-point canvas — the shape the Add menu's
    /// first version laid down on its own (60% of the side, centred), now dragged out from its centre.
    @discardableResult
    private func dragShape(_ object: PrimedObject, on manager: CanvasManager) -> Bool {
        manager.dragOut(object, from: CGPoint(x: 32, y: 32), to: CGPoint(x: 32 + 19.2, y: 32))
    }

    /// A gradient from the artwork's left edge to its right, the full height — what Add → Linear
    /// Gradient laid down on its own before the pen dragged it out.
    @discardableResult
    private func dragGradientAcrossTheCanvas(_ manager: CanvasManager) -> Bool {
        manager.dragOut(.gradient, from: CGPoint(x: 0, y: 32), to: CGPoint(x: 64, y: 32))
    }


    func testAddedObjectsAndStreamsRefuseAFullNodeInsteadOfUsingTheOldUnsuitableSurface() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        XCTAssertTrue(manager.addVectorLayer())
        let existingVector = try XCTUnwrap(manager.layers[0].cels[0].vector)
        XCTAssertTrue(manager.addValueLayer())
        let node = try XCTUnwrap(manager.addCompositorNode(op: .mix(.normal)))
        for index in manager.layers.indices { manager.layers[index].parentFolderID = node }
        let ids = manager.layers.map(\.id), active = manager.currentLayerIndex
        manager.history.removeAll()
        XCTAssertNil(manager.drawingSurfaceForNewObject(vectorOnly: true))
        XCTAssertFalse(dragShape(.rectangle, on: manager))
        manager.currentLayerIndex = 0
        XCTAssertNil(manager.insertStream(host: "127.0.0.1", port: 4567,
            status: StreamStatus(source: .init(kind: "window", name: "Capacity fixture"),
                                 width: 64, height: 64, fps: 30, streaming: true)))
        XCTAssertTrue(existingVector.streams.isEmpty, "A refused stream cannot land on the previously selected vector")
        manager.currentLayerIndex = active
        XCTAssertEqual(manager.layers.map(\.id), ids)
        XCTAssertEqual(manager.currentLayerIndex, active)
        XCTAssertTrue(manager.history.undoStack.isEmpty)
        XCTAssertEqual(manager.layers[active].kind, .value)
        manager.layers[0].parentFolderID = nil
        XCTAssertTrue(dragShape(.rectangle, on: manager))
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1)
        let image = try XCTUnwrap(flattened(manager, layerIndex: manager.currentLayerIndex))
        XCTAssertGreaterThan(pixel(image, 32, 32)[3], 200, "The admitted object actually draws")
    }

    // MARK: - (129) Rectangle and Ellipse

    /// **The object is the fill tool's own kind, in the brush colour, centred on the press.** A
    /// stored-field assertion on purpose — the picture is the next two tests' — because "what kind of
    /// element" is the whole of the ruling: *"make it the same type of shape as what the fill tool
    /// lays down."*
    ///
    /// Mutation caught: laying the rectangle down as anything but a `VectorFillElement` (a stroke, a
    /// smart shape) leaves `fills` empty.
    func testARectangleIsAFillElementOfTheBrushColourCentredOnThePress() throws {
        let (manager, _, vector) = vectorFixture()
        manager.brushColor = red
        XCTAssertTrue(dragShape(.rectangle, on: manager))

        let fill = try XCTUnwrap(vector.elements.compactMap(\.fill).first, "the rectangle is a fill element")
        XCTAssertEqual(vector.elements.count, 1, "…and nothing else was laid down")
        XCTAssertEqual(fill.solidColor, CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                       "the brush colour, as the fill tool paints it")
        let box = try XCTUnwrap(fill.cgPath).boundingBoxOfPath
        XCTAssertEqual(box.midX, 32, accuracy: 0.01)
        XCTAssertEqual(box.midY, 32, accuracy: 0.01)
        XCTAssertEqual(box.width, 38.4, accuracy: 0.01, "twice the distance the pen travelled")
        XCTAssertEqual(box.width, box.height, accuracy: 0.01, "a square")
    }

    /// **Solid means every pixel inside is the colour, and the ellipse is an ellipse.** The rectangle's
    /// corner pixel is inked; the ellipse's is not, while the centre of both is.
    ///
    /// Mutation caught: swapping `.ellipse`'s path for the rectangle's inks the ellipse's corner.
    func testARectangleAndAnEllipseAreSolidAndTheEllipseLeavesItsCorners() throws {
        let rect = vectorFixture()
        rect.manager.brushColor = red
        XCTAssertTrue(dragShape(.rectangle, on: rect.manager))
        let rectImage = try XCTUnwrap(try flattened(rect.manager, layerIndex: rect.layerIndex))
        let ellipse = vectorFixture()
        ellipse.manager.brushColor = red
        XCTAssertTrue(dragShape(.ellipse, on: ellipse.manager))
        let ellipseImage = try XCTUnwrap(try flattened(ellipse.manager, layerIndex: ellipse.layerIndex))

        // The shape spans 12.8…51.2; (16, 16) is inside the square and outside the circle.
        XCTAssertEqual(pixel(rectImage, 32, 32), [255, 0, 0, 255], "the rectangle is solid at its centre")
        XCTAssertEqual(pixel(rectImage, 16, 16), [255, 0, 0, 255], "…and at its corner")
        XCTAssertEqual(pixel(ellipseImage, 32, 32), [255, 0, 0, 255], "the ellipse is solid at its centre")
        XCTAssertEqual(pixel(ellipseImage, 16, 16)[3], 0, "…and leaves the corner of its bounding box bare")
        XCTAssertEqual(pixel(rectImage, 4, 4)[3], 0, "nothing outside the shape is inked")
    }

    /// **A placed shape raises no Move box**: the pen sized it as it went down, so there is nothing
    /// left to size, and the lift hands the canvas back to the tool the artist had.
    func testAPlacedShapeRaisesNoMoveBoxAndHandsTheToolBack() throws {
        let (manager, _, vector) = vectorFixture()
        manager.selectedTool = .pencil
        XCTAssertTrue(dragShape(.rectangle, on: manager))

        XCTAssertNil(manager.vectorFloat, "no Move box is raised")
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1, "the shape is on the layer")
        XCTAssertEqual(manager.selectedTool, .pencil, "the tool the artist had is back")
        XCTAssertNil(manager.primedObject, "and nothing is primed any more")
    }

    /// **A raster layer gets pixels through the fill tool's raster arm, and no box.** There is no
    /// element to lift, so the tier's own limit shows: the shape lands, and sizing it is Move's
    /// lasso route.
    func testAShapeOnARasterLayerIsPaintedIntoTheCelWithNoMoveBox() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.brushColor = red
        let baseline = steps(manager)
        XCTAssertTrue(dragShape(.rectangle, on: manager))

        XCTAssertNil(manager.vectorFloat, "a raster shape raises no Move box")
        XCTAssertEqual(manager.layers.count, 1, "and needs no new layer")
        let image = try XCTUnwrap(try flattened(manager, layerIndex: 0))
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

        XCTAssertTrue(dragShape(.ellipse, on: manager))

        XCTAssertEqual(manager.layers.count, layerCount + 1)
        XCTAssertEqual(manager.activeLayerKind, .vector)
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels.first?.vector)
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1, "the shape is on it")
    }

    /// One undo step takes the shape away, and a redo puts it back.
    func testAShapeIsOneUndoStep() throws {
        let (manager, _, vector) = vectorFixture()
        XCTAssertTrue(dragShape(.rectangle, on: manager))
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
        manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath)
        let baseline = steps(manager)
        manager.fillSelection()
        XCTAssertEqual(vector.elements.compactMap(\.fill).count, 1)
        XCTAssertEqual(steps(manager) - baseline, 1)
    }

    // MARK: - (128) The gradient is an object

    /// **Add → Linear Gradient, dragged from edge to edge, lays a gradient fill over the artwork and the
    /// pixels ramp along its axis** — black at the left edge, white at the right, mid-grey between, and
    /// constant down any column. The two-operands trap applied: a fixture that checked `paint` would stay green against
    /// a draw path that never read it.
    ///
    /// Mutation caught: drawing `.linearGradient` with the solid arm's fill leaves every pixel one
    /// colour and the ramp assertions go red.
    func testALinearGradientRampsAcrossTheArtworkAndIsConstantDownAColumn() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        XCTAssertTrue(dragGradientAcrossTheCanvas(manager))
        manager.commitAllInteractiveState()

        XCTAssertEqual(vector.elements.compactMap(\.fill).compactMap(\.gradient).count, 1,
                       "the gradient is an element of the vector layer")
        let image = try XCTUnwrap(try flattened(manager, layerIndex: layerIndex))
        let left = pixel(image, 0, 32), middle = pixel(image, side / 2, 32), right = pixel(image, side - 1, 32)
        XCTAssertLessThan(left[0], 12, "black at the left edge")
        XCTAssertGreaterThan(right[0], 243, "white at the right edge")
        let oklabMiddle = Int((ColorMath.mixOklab((0, 0, 0), (1, 1, 1), 0.5).r * 255).rounded())
        XCTAssertEqual(middle[0], oklabMiddle, accuracy: 6,
                       "the middle is the Oklab mean, 99 — a ramp, not a step, and not sRGB's 128")
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

        // A coincident ramp is its end colour, including after a nonuniform affine.
        let collapsed = LinearGradientPaint(start: .init(red: 0, green: 0, blue: 0, alpha: 1),
                                           end: .init(red: 1, green: 1, blue: 1, alpha: 1),
                                           from: CGPoint(x: 20, y: 24), to: CGPoint(x: 20, y: 24))
        let collapsedFill = VectorElement.fill(VectorFillElement(
            path: CGPath(rect: CGRect(x: 16, y: 16, width: 16, height: 16), transform: nil),
            paint: .linearGradient(collapsed)))
        let stretched = VectorCanvas.mapping(collapsedFill,
            throughStretch: CGAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: -24, ty: 0))
        let collapsedCanvas = VectorCanvas(size: CanvasFixture.canvasSize, elements: [stretched])
        let collapsedImage = try XCTUnwrap(collapsedCanvas.render()?.cgImage)
        XCTAssertEqual(pixel(collapsedImage, 32, 20), [255, 255, 255, 255],
                       "a coincident gradient keeps its end colour through Freeform")
    }

    /// **The ramp blends in Oklab, not in sRGB** — the owner's *"is the linear gradient oklab?"*, and it
    /// was not. Red to green is the pair the two spaces disagree about most: a straight line through
    /// the gamma-encoded channels runs red 255 to 0 and green 0 to 255 through a dark (128, 128, 0)
    /// olive, where Oklab keeps the lightness up through (208, 168, 0). The pixels at four positions
    /// along the ramp are the Oklab mix at that position to within the sampling's own error, and the
    /// middle is nowhere near the sRGB one.
    ///
    /// Mutation caught: drawing the two stops through a plain two-stop `CGGradient` puts (128, 128, 0)
    /// in the middle and every assertion below goes red.
    func testALinearGradientBlendsInOklabNotInSRGB() throws {
        let (manager, layerIndex, _) = vectorFixture()
        XCTAssertTrue(dragGradientAcrossTheCanvas(manager))
        manager.setGradientColour(.start, to: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
        manager.setGradientColour(.end, to: Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1))
        manager.commitAllInteractiveState()
        let image = try XCTUnwrap(try flattened(manager, layerIndex: layerIndex))

        for x in [8, 20, 31, 32, 44, 56] {
            let t = (Double(x) + 0.5) / Double(side)
            let expected = ColorMath.mixOklab((1, 0, 0), (0, 1, 0), t)
            let got = pixel(image, x, 32)
            for (channel, want) in [(0, expected.r), (1, expected.g), (2, expected.b)] {
                XCTAssertEqual(got[channel], Int((want * 255).rounded()), accuracy: 4,
                               "x = \(x), channel \(channel): the ramp's colour at t = \(t) is the Oklab mix")
            }
        }
        let middle = pixel(image, 32, 32)
        XCTAssertGreaterThan(middle[0], 190, "the middle keeps its red up (Oklab: 208), where sRGB's has dropped to 128")
        XCTAssertGreaterThan(middle[1], 150, "…and its green (Oklab: 168)")
    }

    /// The ramp handed to Core Graphics, without drawing it: 257 stops, the Oklab mix at each one, the
    /// two ends exactly the two colours (the round trip is byte exact), and alpha a straight line
    /// between the two — which is how the two-stop gradient this replaced treated it.
    func testTheRampComponentsAreTheOklabMixAtEveryStopAndAlphaIsLinear() {
        let start = CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        let end = CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 0.2)
        let gradient = LinearGradientPaint(start: start, end: end, from: .zero, to: CGPoint(x: 10, y: 0))
        let ramp = gradient.rampComponents
        let count = LinearGradientPaint.rampStopCount
        XCTAssertEqual(ramp.count, count * 4)
        XCTAssertEqual(LinearGradientPaint.rampLocations.count, count)
        XCTAssertEqual(LinearGradientPaint.rampLocations.first, 0)
        XCTAssertEqual(LinearGradientPaint.rampLocations.last, 1)

        func stop(_ i: Int) -> [Double] { ramp[(i * 4)..<(i * 4 + 4)].map(Double.init) }
        XCTAssertEqual(stop(0)[0], 0.9, accuracy: 1.0 / 255)
        XCTAssertEqual(stop(0)[2], 0.1, accuracy: 1.0 / 255)
        XCTAssertEqual(stop(count - 1)[1], 0.3, accuracy: 1.0 / 255)
        XCTAssertEqual(stop(count - 1)[2], 0.9, accuracy: 1.0 / 255)
        for i in [1, 64, 128, 200, count - 2] {
            let t = Double(i) / Double(count - 1)
            let mix = ColorMath.mixOklab((0.9, 0.2, 0.1), (0.1, 0.3, 0.9), t)
            XCTAssertEqual(stop(i)[0], mix.r, accuracy: 1e-6, "stop \(i) red")
            XCTAssertEqual(stop(i)[1], mix.g, accuracy: 1e-6, "stop \(i) green")
            XCTAssertEqual(stop(i)[2], mix.b, accuracy: 1e-6, "stop \(i) blue")
            XCTAssertEqual(stop(i)[3], 1 + (0.2 - 1) * t, accuracy: 1e-6, "stop \(i) alpha is linear")
        }
        XCTAssertNotEqual(stop(128)[1], (0.2 + 0.3) / 2, accuracy: 0.01,
                          "the middle is not the straight sRGB average")
    }

    /// **The panel's angle turns the ramp, live, and the whole session is one undo step.** 90 degrees
    /// runs top to bottom: the rows now differ and a row is constant — in the picture the panel's
    /// window shows, while the document still holds the left-to-right gradient. Undo returns to the
    /// left-to-right gradient exactly.
    func testTurningTheAngleRunsTheRampDownTheCanvasAsOneUndoStep() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        dragGradientAcrossTheCanvas(manager)
        let baseline = steps(manager)
        let original = try XCTUnwrap(manager.editedGradient)

        let version = vector.version
        manager.setGradientAngle(.pi / 2)
        manager.setGradientAngle(.pi / 2)   // a second write of the same value changes nothing
        XCTAssertEqual(vector.version, version, "a tick holds the picture and writes nothing")
        XCTAssertEqual(vector.elements.compactMap(\.fill).first?.gradient, original,
                       "the document still holds the gradient the panel opened on")
        let documentImage = try XCTUnwrap(try flattened(manager, layerIndex: layerIndex))
        XCTAssertEqual(pixel(documentImage, 32, 0)[0], pixel(documentImage, 32, side - 1)[0], accuracy: 1,
                       "the document's own picture still runs left to right: a column is constant")
        let image = try XCTUnwrap(try heldFlattened(manager))
        XCTAssertLessThan(pixel(image, 32, 0)[0], 12, "black at the top")
        XCTAssertGreaterThan(pixel(image, 32, side - 1)[0], 243, "white at the bottom")
        // Within one 8-bit step: at 90 degrees `cos` is 6e-17 rather than 0, and with 257 stops a
        // row's pixel centre can land exactly on a stop, where that is enough to tip a rounding.
        for channel in 0..<3 {
            XCTAssertEqual(pixel(image, 4, 20)[channel], pixel(image, 60, 20)[channel], accuracy: 1,
                           "constant along a row (channel \(channel))")
        }
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
        dragGradientAcrossTheCanvas(manager)
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
    /// `documentVersion` is part of `LayerContentVersion`, and `FrameBakeKey` digests that version —
    /// so a recoloured gradient names a different frame on disk. Without this a baked frame would be
    /// served with the old colours.
    func testEditingAGradientMovesTheLayerContentVersionAndTheBakeKey() throws {
        let (manager, layerIndex, _) = vectorFixture()
        dragGradientAcrossTheCanvas(manager)
        manager.commitAllInteractiveState()
        let id = try XCTUnwrap(manager.layers[layerIndex].cels[0].vector?.elements.first?.id)

        func digest() throws -> String {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, quality: .full,
                                                                includeBackground: true, sizing: .native))
            return FrameBakeKey(recipe: recipe, renderResolution: .full,
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
        dragGradientAcrossTheCanvas(manager)
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

        for transform in [CGAffineTransform(translationX: 3, y: 7),
                          CGAffineTransform(rotationAngle: .pi / 7),
                          CGAffineTransform(scaleX: 1.7, y: 1.7),
                          CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 64, ty: 0)] {
            let ordinary = try XCTUnwrap(VectorCanvas.mapping(.fill(fill), throughStretch: transform).fill?.gradient)
            XCTAssertEqual([ordinary.from, ordinary.to],
                           [gradient.from.applying(transform), gradient.to.applying(transform)],
                           "similarities and reflection retain their exact pushed endpoints")
        }

        let diagonal = LinearGradientPaint(start: gradient.start, end: gradient.end,
                                          from: CGPoint(x: 3, y: 5), to: CGPoint(x: 19, y: 21))
        let diagonalFill = fill.reshaped(to: try XCTUnwrap(fill.cgPath), paint: .linearGradient(diagonal))
        for singular in [CGAffineTransform(a: 0, b: 0, c: 0, d: 1, tx: 7, ty: 11),
                         CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 7, ty: 11)] {
            let mapped = try XCTUnwrap(VectorCanvas.mapping(.fill(diagonalFill), throughStretch: singular).fill?.gradient)
            XCTAssertEqual([mapped.from, mapped.to],
                           [diagonal.from.applying(singular), diagonal.to.applying(singular)],
                           "a singular affine retains the existing endpoint contract, without an inverse")
        }

        let coincident = LinearGradientPaint(start: gradient.start, end: gradient.end,
                                            from: CGPoint(x: 6, y: 9), to: CGPoint(x: 6, y: 9))
        let affine = CGAffineTransform(a: 2, b: 0, c: 1, d: 1, tx: 3, ty: 4)
        let coincidentFill = fill.reshaped(to: try XCTUnwrap(fill.cgPath), paint: .linearGradient(coincident))
        let mappedCoincident = try XCTUnwrap(VectorCanvas.mapping(.fill(coincidentFill), throughStretch: affine).fill?.gradient)
        XCTAssertEqual([mappedCoincident.from, mappedCoincident.to],
                       [coincident.from.applying(affine), coincident.to.applying(affine)],
                       "coincident endpoints remain coincident at their mapped point")
    }

    /// **A lasso Move of a gradient is a real Move**: lifted by the lasso, nudged, baked — and the
    /// ramp is where the fill went, not left behind at the old coordinates.
    func testAMovedGradientFillRampsWhereItWentNotWhereItWas() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let rect = CGRect(x: 0, y: 0, width: 32, height: 64)
        vector.addFill(path: CGPath(rect: rect, transform: nil),
                       paint: .linearGradient(.spanning(rect, angle: 0)))
        let id = try XCTUnwrap(vector.elements.first?.id)
        XCTAssertTrue(manager.beginVectorMove(ofElementIDs: [id]))
        var frame = try XCTUnwrap(manager.vectorFloat).frame.transform
        frame.position.x += 32
        manager.nudgeVectorFloat(to: frame)
        manager.commitAllInteractiveState()

        let image = try XCTUnwrap(try flattened(manager, layerIndex: layerIndex))
        XCTAssertEqual(pixel(image, 8, 32)[3], 0, "nothing is left at the old position")
        let near = pixel(image, 33, 32), far = pixel(image, 62, 32)
        XCTAssertLessThan(near[0], 20, "black at the moved fill's left edge")
        XCTAssertGreaterThan(far[0], 235, "white at its right edge")

        // A diagonal ramp under Freeform must carry its interior colours, not only its endpoints.
        // The reference draws ORIGINAL geometry under a native CTM, without mapping the paint or
        // resampling a bitmap. The actual image comes from the real Move owner and cel flatten.
        let (stretchedManager, stretchedLayer, stretchedVector) = vectorFixture()
        let diagonalRect = CGRect(x: 16, y: 16, width: 16, height: 16)
        stretchedVector.addFill(path: CGPath(rect: diagonalRect, transform: nil),
                                paint: .linearGradient(.fresh(from: CGPoint(x: 16, y: 16),
                                                              to: CGPoint(x: 32, y: 32))))
        let originalElements = stretchedVector.elements
        let diagonalID = try XCTUnwrap(originalElements.first?.id)
        XCTAssertTrue(stretchedManager.beginVectorMove(ofElementIDs: [diagonalID]))
        var stretchedFrame = try XCTUnwrap(stretchedManager.vectorFloat).frame.transform
        stretchedFrame.scale *= sqrt(2)
        stretchedManager.nudgeVectorFloat(to: stretchedFrame, aspect: 2, stretchAxis: 0)
        XCTAssertTrue(stretchedManager.commitAllInteractiveState())
        let stretchedImage = try XCTUnwrap(flattened(stretchedManager, layerIndex: stretchedLayer))

        // x2/y1 about (24,24): the original interior point (28,20) lands at (32,20).
        let referenceAffine = CGAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: -24, ty: 0)
        let referenceCanvas = VectorCanvas(size: CanvasFixture.canvasSize, elements: originalElements)
        let original = referenceCanvas.freeze(quality: .full)
        let referenceFormat = PixelOps.transparentFormat()
        referenceFormat.preferredRange = .standard
        let nativeReference = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize,
            format: referenceFormat).image { context in
                context.cgContext.concatenate(referenceAffine)
                _ = original.draw(into: context.cgContext,
                                  frameRect: CGRect(origin: .zero, size: CanvasFixture.canvasSize),
                                  quality: .full)
            }
        let referenceImage = try XCTUnwrap(nativeReference.cgImage)
        for (name, picture) in [("affine-gradient-actual-move", UIImage(cgImage: stretchedImage)),
                                ("affine-gradient-native-ctm-reference", nativeReference)] {
            let attachment = XCTAttachment(image: picture)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let movedFill = try XCTUnwrap(stretchedVector.elements.first?.fill)
        let movedBounds = try XCTUnwrap(movedFill.cgPath).boundingBoxOfPath
        let boundsError = [movedBounds.minX - 8, movedBounds.minY - 16,
                           movedBounds.width - 32, movedBounds.height - 16].map { abs($0) }.max() ?? .infinity
        XCTAssertLessThanOrEqual(boundsError, 0.00001, "PREMISE: Freeform reached x2/y1 about the fill centre")
        let sourceGradient = try XCTUnwrap(originalElements.first?.fill?.gradient)
        let mappedGradient = try XCTUnwrap(movedFill.gradient)
        let sourceSpan = CGVector(dx: sourceGradient.to.x - sourceGradient.from.x,
                                  dy: sourceGradient.to.y - sourceGradient.from.y)
        let mappedSpan = CGVector(dx: mappedGradient.to.x - mappedGradient.from.x,
                                  dy: mappedGradient.to.y - mappedGradient.from.y)
        // Independent source-space projection through the literal reference CTM's inverse. Three
        // noncollinear actual pixel centres distinguish a transported field from pushed endpoints.
        let inverseReference = referenceAffine.inverted()
        for point in [CGPoint(x: 32.5, y: 20.5), CGPoint(x: 16.5, y: 20.5), CGPoint(x: 32.5, y: 28.5)] {
            let sourcePoint = point.applying(inverseReference)
            let expectedFraction = ((sourcePoint.x - sourceGradient.from.x) * sourceSpan.dx
                + (sourcePoint.y - sourceGradient.from.y) * sourceSpan.dy)
                / (sourceSpan.dx * sourceSpan.dx + sourceSpan.dy * sourceSpan.dy)
            let actualFraction = ((point.x - mappedGradient.from.x) * mappedSpan.dx
                + (point.y - mappedGradient.from.y) * mappedSpan.dy)
                / (mappedSpan.dx * mappedSpan.dx + mappedSpan.dy * mappedSpan.dy)
            XCTAssertTrue(actualFraction.isFinite && expectedFraction.isFinite
                          && abs(actualFraction - expectedFraction) <= 1e-12,
                          "Freeform must carry the scalar field at \(point): actual \(actualFraction), source \(expectedFraction)")
        }
        let actualInterior = pixel(stretchedImage, 32, 20), referenceInterior = pixel(referenceImage, 32, 20)
        XCTAssertEqual([actualInterior[3], referenceInterior[3]], [255, 255],
                       "PREMISE: both whole images paint the corresponding interior pixel")
        XCTAssertEqual([pixel(stretchedImage, 4, 20)[3], pixel(referenceImage, 4, 20)[3]], [0, 0],
                       "PREMISE: neither image paints outside the moved path")
        XCTAssertTrue((1..<255).contains(referenceInterior[0]),
                      "PREMISE: the native reference pixel lies inside the nonblank ramp, not an end colour")
        // At pixel centre(32.5,20.5), inverse x2/y1 gives source(28.25,20.5), hence t67/128.
        // Neutral Oklab has linear RGB=L³. Judge each drawn image against this independent colour;
        // native-CTM and mapped-identity CoreGraphics gradients need not quantize to the same byte.
        let fraction = 67.0 / 128.0
        let linearGrey = fraction * fraction * fraction
        let expectedGrey = Int((255 * (1.055 * pow(linearGrey, 1.0 / 2.4) - 0.055)).rounded())
        let actualDifference = (0..<3).map { abs(actualInterior[$0] - expectedGrey) }.max() ?? 0
        let referenceDifference = (0..<3).map { abs(referenceInterior[$0] - expectedGrey) }.max() ?? 0
        let actualFormat = "\(stretchedImage.bitsPerComponent)bpc/\(stretchedImage.bitsPerPixel)bpp, \(String(describing: stretchedImage.colorSpace?.name))"
        let nativeFormat = "\(referenceImage.bitsPerComponent)bpc/\(referenceImage.bitsPerPixel)bpp, \(String(describing: referenceImage.colorSpace?.name))"
        XCTAssertLessThanOrEqual(actualDifference, 2,
            "Freeform changed an interior colour: moved \(actualInterior) [\(actualFormat)], analytic grey \(expectedGrey)")
        XCTAssertLessThanOrEqual(referenceDifference, 2,
            "Native CTM reference \(referenceInterior) [\(nativeFormat)] must match analytic grey \(expectedGrey)")
    }

    // MARK: - The document format

    /// Flat and gradient fills encode their own paint fields and round-trip in the current format.
    func testDocumentFormatSeparatesFlatAndGradientPaintAndRoundTripsBoth() throws {
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

        let flatPayload = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(flat)) as? [String: Any])
        XCTAssertEqual(Set(flatPayload.keys), ["id", "pathData", "color", "opacity", "evenOddFill"],
                       "the flat payload contains only its current geometry and paint fields")
        let restored = try JSONDecoder().decode(VectorFillElement.self,
                                                from: JSONSerialization.data(withJSONObject: flatPayload))
        XCTAssertEqual(restored.solidColor, flat.solidColor)
    }

    // MARK: - Mend All Fills

    private func mendReferenceStroke(_ points: [CGPoint], size: CGFloat) -> VectorStroke {
        let brush = Brush(name: "mend reference", tip: .round, size: size,
                          dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1))
        return VectorStroke(brush: brush, color: CodableColor(UIColor.black), size: size, opacity: 1,
                            samples: StrokeSamples(points: points), seed: 0x7354)
    }

    /// Two independently drawn cels with different line art, plus a linked generated cel which must
    /// remain derived. The saved paths contain an attached stroke gap and an intentional paper hole.
    private func mendFixture() throws -> (manager: CanvasManager, layer: Int, vectors: [VectorCanvas], fills: [VectorFillElement]) {
        _ = try XCTUnwrap(MetalFillEngine.shared, "the shared Metal fill engine is required")
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(0, 6), (6, 6), (12, 6)])
        let field = CGRect(x: 10, y: 10, width: 44, height: 44)
        let hole = CGRect(x: 16, y: 16, width: 12, height: 12)
        let gaps = [CGRect(x: 30, y: 32, width: 24, height: 3),
                    CGRect(x: 32, y: 30, width: 3, height: 24)]
        manager.layers[0].kind = .vector
        for celIndex in 0..<3 {
            let frame = mendReferenceStroke([CGPoint(x: 9, y: 9), CGPoint(x: 55, y: 9),
                CGPoint(x: 55, y: 55), CGPoint(x: 9, y: 55), CGPoint(x: 9, y: 9)], size: 2)
            let hole = mendReferenceStroke([CGPoint(x: 17, y: 17), CGPoint(x: 27, y: 17),
                CGPoint(x: 27, y: 27), CGPoint(x: 17, y: 27), CGPoint(x: 17, y: 17)], size: 2)
            let body = mendReferenceStroke(celIndex == 0
                ? [CGPoint(x: 31.5, y: 33.5), CGPoint(x: 54, y: 33.5)]
                : [CGPoint(x: 33.5, y: 31.5), CGPoint(x: 33.5, y: 54)], size: 3)
            manager.layers[0].cels[celIndex].vector = VectorCanvas(size: CanvasFixture.canvasSize,
                strokes: [frame, hole, body])
        }
        manager.addVectorLayer()
        let layer = manager.currentLayerIndex
        manager.setFillReference(layerIndex: layer, isReference: false)
        CanvasFixture.setCelLayout(manager, layerIndex: layer, [(0, 6), (6, 6), (12, 6)])
        var vectors: [VectorCanvas] = []
        var fills: [VectorFillElement] = []
        for celIndex in 0..<3 {
            let path = CGMutablePath()
            path.addRect(field)
            path.addRect(hole)
            // An even-odd contour represents the real saved geometry, including its open branch
            // notch. Subtraction avoids adding another overlapping contour at the field boundary.
            let source = path.normalized(using: .evenOdd)
                .subtracting(CGPath(rect: gaps[min(celIndex, 1)], transform: nil), using: .winding)
            let paint: FillPaint = celIndex == 0
                ? .linearGradient(.spanning(field, angle: 0))
                : .solid(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
            var fill = VectorFillElement(path: source, paint: paint, opacity: 0.6, evenOddFill: true)
            fill.animationGroupID = UUID()
            let vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [.fill(fill)])
            manager.layers[layer].cels[celIndex].vector = vector
            if celIndex == 2 {
                manager.layers[layer].cels[celIndex].interpolation = InterpolationRecipe(mode: .generate)
            }
            vectors.append(vector)
            fills.append(fill)
        }
        manager.fillSettings.threshold = 0.15
        manager.fillSettings.mendReach = 12
        manager.currentFrame = 0
        return (manager, layer, vectors, fills)
    }

    func testMendAllFillsUsesEachCelsReferencesPreservesPaintHolesAndDerivedCelsAsOneUndo() async throws {
        let fixture = try mendFixture()
        let manager = fixture.manager
        let before = try fixture.vectors.map { try XCTUnwrap($0.render()?.cgImage) }
        XCTAssertEqual(pixel(before[0], 40, 33)[3], 0, "PREMISE: horizontal attached stem is bare")
        XCTAssertEqual(pixel(before[1], 33, 40)[3], 0, "PREMISE: second cel has a vertical gap")
        let baseline = steps(manager)
        let outcome = await manager.mendAllFills(layerIndex: fixture.layer)
        XCTAssertEqual(outcome, .changed(2))
        XCTAssertEqual(steps(manager) - baseline, 1, "the entire layer is one edit")
        XCTAssertEqual(manager.history.undoStack.last?.label, .mendAllFills)
        let changedArchives = fixture.vectors.prefix(2).compactMap { $0.elements.first?.fill?.pathData.count }.reduce(0, +)
        let originalArchives = fixture.fills.prefix(2).map { $0.pathData.count }.reduce(0, +)
        XCTAssertEqual(manager.history.undoStack.last?.cost,
                       2 * MemoryLayout<VectorElement>.stride + originalArchives + changedArchives,
                       "The shared accountant prices the two actual archive replacements once, with no fill-only surcharge.")
        let after = try fixture.vectors.map { try XCTUnwrap($0.render()?.cgImage) }
        XCTAssertEqual(pixel(after[0], 40, 33), pixel(after[0], 40, 42),
                       "the gradient crosses the repaired stem with its original paint and opacity")
        XCTAssertEqual(pixel(after[1], 33, 40), pixel(after[1], 42, 40),
                       "the second cel uses its own vertical reference, not the playhead's horizontal line")
        for index in 0..<2 {
            let changed = try XCTUnwrap(fixture.vectors[index].elements.first?.fill)
            let original = fixture.fills[index]
            XCTAssertEqual(changed.id, original.id)
            XCTAssertEqual(changed.paint, original.paint)
            XCTAssertEqual(changed.opacity, original.opacity)
            XCTAssertEqual(changed.animationGroupID, original.animationGroupID)
            XCTAssertEqual(changed.evenOddFill, original.evenOddFill)
            XCTAssertEqual(pixel(after[index], 20, 20)[3], 0, "intentional paper hole stays bare")
            XCTAssertEqual(pixel(after[index], 55, 33)[3], 0, "outer outline stays bare")
            XCTAssertEqual(pixel(after[index], 5, 5)[3], 0, "exterior paper stays bare")
            XCTAssertEqual(pixel(after[index], 12, 40), pixel(before[index], 12, 40),
                           "existing paint away from the gap is pixel-exact")
        }
        XCTAssertEqual(fixture.vectors[2].elements.first?.fill?.pathData, fixture.fills[2].pathData,
                       "linked generated content is never flattened or rewritten")
        XCTAssertEqual(manager.layers[fixture.layer].cels[2].interpolation?.mode, .generate)
        manager.undo()
        for index in 0..<3 {
            XCTAssertEqual(fixture.vectors[index].elements.first?.fill?.pathData, fixture.fills[index].pathData)
        }
        XCTAssertEqual(pixel(try XCTUnwrap(fixture.vectors[0].render()?.cgImage), 40, 33)[3], 0,
                       "one undo restores the drawn horizontal gap")
        XCTAssertEqual(pixel(try XCTUnwrap(fixture.vectors[1].render()?.cgImage), 33, 40)[3], 0,
                       "and the drawn vertical gap")
        manager.redo()
        for index in 0..<2 {
            XCTAssertEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(fixture.vectors[index].render()?.cgImage)),
                           CanvasFixture.rgbaBytes(after[index]), "redo restores the exact whole picture")
        }
        let repeatedBaseline = steps(manager)
        let repeated = await manager.mendAllFills(layerIndex: fixture.layer)
        XCTAssertEqual(repeated, .unchanged,
                       "an already repaired layer adds no new geometry")
        XCTAssertEqual(steps(manager), repeatedBaseline, "no empty undo step on a repeat")
    }

    func testMendAllFillsRefusesAnUndoStepOverBudgetBeforeChangingAnyCel() async throws {
        let fixture = try mendFixture()
        let manager = fixture.manager
        manager.history.maxCost = 1
        let baseline = steps(manager)
        let outcome = await manager.mendAllFills(layerIndex: fixture.layer)
        XCTAssertEqual(outcome, .exceedsBudget)
        for index in 0..<3 {
            XCTAssertEqual(fixture.vectors[index].elements.first?.fill?.pathData, fixture.fills[index].pathData,
                           "a capacity refusal leaves every cel untouched")
        }
        XCTAssertEqual(steps(manager), baseline)
    }

    func testMendAllFillsExcludesItsOwnBlackPaintWhileTheTargetRemainsAReference() async throws {
        let fixture = try mendFixture()
        let manager = fixture.manager
        manager.setFillReference(layerIndex: fixture.layer, isReference: true)
        for index in 0..<2 {
            var fill = fixture.fills[index]
            fill.paint = .solid(CodableColor(red: 0, green: 0, blue: 0, alpha: 1))
            fill.opacity = 1
            fixture.vectors[index].restoreElements([.fill(fill)], changedInk: nil)
        }
        let before = try fixture.vectors.prefix(2).map { try XCTUnwrap($0.render()?.cgImage) }
        XCTAssertEqual(pixel(before[0], 40, 33)[3], 0, "PREMISE: the saved black fill has a horizontal gap")
        XCTAssertEqual(pixel(before[1], 33, 40)[3], 0, "PREMISE: the second fill has a vertical gap")
        XCTAssertEqual(pixel(before[0], 40, 42), [0, 0, 0, 255], "PREMISE: paint matches the black reference ink")

        let outcome = await manager.mendAllFills(layerIndex: fixture.layer)

        XCTAssertEqual(outcome, .changed(2))
        let after = try fixture.vectors.prefix(2).map { try XCTUnwrap($0.render()?.cgImage) }
        XCTAssertEqual(pixel(after[0], 40, 33), [0, 0, 0, 255], "own paint cannot turn the line into passable reference colour")
        XCTAssertEqual(pixel(after[1], 33, 40), [0, 0, 0, 255], "each cel excludes its own fill")
        for image in after {
            XCTAssertEqual(pixel(image, 20, 20)[3], 0, "the intentional hole remains empty")
            XCTAssertEqual(pixel(image, 55, 42)[3], 0, "the original exterior edge does not grow")
        }
        XCTAssertTrue(manager.layers[fixture.layer].isFillReference, "the artist's reference choice stays on")
    }

    func testMendAllFillsRepairsRealBucketFillsAtDefaultOverlapWithoutChangingTheirOutsideEdges() async throws {
        _ = try XCTUnwrap(MetalFillEngine.shared)
        let size = CGSize(width: 128, height: 128)
        let width = Int(size.width), height = Int(size.height)
        for attached in [true, false] {
            let manager = CanvasFixture.manager(layerCount: 1)
            manager.canvasSize = size
            manager.layers[0].kind = .vector
            manager.layers[0].cels[0].raster = .empty(size: size)
            let stroke = attached ? CGRect(x: 16, y: 59, width: 49, height: 10)
                                  : CGRect(x: 54, y: 44, width: 10, height: 40)
            let interiorStroke = attached ? CGRect(x: 26, y: 59, width: 39, height: 10) : stroke
            let frame = mendReferenceStroke([CGPoint(x: 21, y: 21), CGPoint(x: 107, y: 21),
                CGPoint(x: 107, y: 107), CGPoint(x: 21, y: 107), CGPoint(x: 21, y: 21)], size: 10)
            let body = mendReferenceStroke(attached
                ? [CGPoint(x: 21, y: 64), CGPoint(x: 60, y: 64)]
                : [CGPoint(x: 59, y: 49), CGPoint(x: 59, y: 79)], size: 10)
            manager.layers[0].cels[0].vector = VectorCanvas(size: size, strokes: [frame, body])
            manager.addVectorLayer()
            let layer = manager.currentLayerIndex
            let vector = try XCTUnwrap(manager.layers[layer].cels[0].vector)
            XCTAssertTrue(manager.layers[layer].isFillReference, "PREMISE: the target keeps its visible reference default")
            XCTAssertEqual(manager.fillSettings.bucketEdgeOverlap, 2, "PREMISE: this is the ordinary bucket overlap")
            manager.setFillMendsGaps(false)
            manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
            manager.beginInteractiveFill(at: CGPoint(x: 40, y: 40))
            manager.endInteractiveFill()
            manager.fillQueue.sync {}
            manager.commitInteractiveFill()
            manager.fillQueue.sync {}

            let saved = try XCTUnwrap(vector.elements.first?.fill, "a real bucket commit creates the saved fill")
            XCTAssertEqual(vector.elements.count, 1)
            let beforeImage = try XCTUnwrap(vector.render()?.cgImage)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(beforeImage))
            XCTAssertEqual(pixel(beforeImage, 40, 40), [255, 0, 0, 255], "PREMISE: the bucket painted ordinary red")
            for position in 0..<10 {
                let x = attached ? 45 : 54 + position
                let y = attached ? 59 + position : 64
                XCTAssertEqual(pixel(beforeImage, x, y)[3], (2..<8).contains(position) ? 0 : 255,
                               "PREMISE: overlap2 covers both sides of the10px stroke, leaving its centre6px bare")
            }
            let baseline = steps(manager)

            let outcome = await manager.mendAllFills(layerIndex: layer)

            XCTAssertEqual(outcome, .changed(1), "the saved default-overlap fill must be mendable")
            XCTAssertEqual(steps(manager) - baseline, 1, "the layer action records one edit")
            let afterImage = try XCTUnwrap(vector.render()?.cgImage)
            let after = try XCTUnwrap(CanvasFixture.rgbaBytes(afterImage))
            XCTAssertEqual(pixel(afterImage, attached ? 45 : 59, 64), [255, 0, 0, 255],
                           "the real saved fill covers the attached or detached stroke's remaining centre")
            let outsideChanges = (0..<(width * height)).filter { index in
                let x = index % width, y = index / width
                guard !interiorStroke.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) else { return false }
                return (0..<4).contains { before[index * 4 + $0] != after[index * 4 + $0] }
            }
            XCTAssertTrue(outsideChanges.isEmpty,
                          "every pixel outside the known interior stroke, including the original outline, stays exact: \(outsideChanges.prefix(6))")
            guard outcome == .changed(1) else { continue }
            manager.undo()
            XCTAssertEqual(vector.elements.first?.fill?.pathData, saved.pathData, "one undo restores the actual bucket contour")
            let restored = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
            XCTAssertTrue(restored == before, "one undo restores the complete original bucket picture")
        }
    }

    func testReferenceExclusionKeepsOtherFillsStrokesStreamsAndOrdinaryRenderMemos() throws {
        let (manager, layer, vector) = vectorFixture()
        let size = CanvasFixture.canvasSize
        let omitted = VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
                                        color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let green = VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 8, height: 8), transform: nil),
                                      color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1))
        let blue = VectorStroke(brush: manager.toolProfiles.brush.preset,
            color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1), size: 8, opacity: 1,
            samples: [VectorSample(x: 24, y: 12, pressure: 1), VectorSample(x: 32, y: 12, pressure: 1)])
        let stream = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8), host: "fixture", port: 47301,
            sourceLabel: "mend reference", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 44, y: 12), scale: 1, rotation: 0))
        vector.restoreElements([.fill(omitted), .fill(green), .stroke(blue), .stream(stream)], changedInk: nil)
        let frame = UIGraphicsImageRenderer(size: stream.naturalSize, format: PixelOps.transparentFormat()).image { context in
            UIColor.yellow.setFill()
            context.fill(CGRect(origin: .zero, size: stream.naturalSize))
        }
        XCTAssertTrue(vector.setStreamFrame(id: stream.id, image: frame, index: 1))
        manager.addVectorLayer()
        let ordinaryLayer = manager.currentLayerIndex
        let ordinary = try XCTUnwrap(manager.layers[ordinaryLayer].cels[0].vector)
        ordinary.addFill(path: CGPath(rect: CGRect(x: 8, y: 44, width: 8, height: 8), transform: nil),
                         color: CodableColor(red: 0, green: 1, blue: 1, alpha: 1))
        XCTAssertFalse(ordinary.hasCachedImage, "PREMISE: the ordinary reference has not rendered")
        let sources = [(layer: manager.layers[layer], cel: manager.layers[layer].cels[0]),
                       (layer: manager.layers[ordinaryLayer], cel: manager.layers[ordinaryLayer].cels[0])]
        let window = FillWindow.fitting(CGRect(origin: .zero, size: size), in: size, pixelBudget: side * side)
        let excluded = (celID: sources[0].cel.id, elementID: omitted.id)
        let bytes = try XCTUnwrap(CanvasManager.compositeReferenceRGBA(references: sources, window: window,
                                                                      excludingElement: excluded))
        func sample(_ x: Int, _ y: Int) -> [Int] {
            let offset = (y * window.workingWidth + x) * 4
            return bytes[offset..<(offset + 4)].map(Int.init)
        }
        XCTAssertEqual(sample(4, 4), [0, 0, 0, 0], "only the addressed fill is absent")
        XCTAssertEqual(sample(12, 12), [0, 255, 0, 255], "another fill remains a reference")
        XCTAssertEqual(sample(28, 12), [0, 0, 255, 255], "same-cel brush marks remain")
        XCTAssertEqual(sample(44, 12), [255, 255, 0, 255], "the stream's current frame remains")
        XCTAssertEqual(sample(12, 48), [0, 255, 255, 255], "the ordinary reference remains")
        XCTAssertTrue(ordinary.hasCachedImage, "ordinary references still populate their shared render memo")
        let walks = ordinary.rasterizations
        XCTAssertEqual(CanvasManager.compositeReferenceRGBA(references: sources, window: window,
                                                           excludingElement: excluded), bytes)
        XCTAssertEqual(ordinary.rasterizations, walks, "a repeated ordinary reference reuses its picture")
    }

    func testMendAllFillsDiscardsEveryPreparedCelWhenReferenceOrNeighbourRenderingRefuses() async throws {
        defer { VectorRenderCache.removeAll() }
        for failsInReference in [true, false] {
            let fixture = try mendFixture()
            let manager = fixture.manager
            // The existing bitmap-refusal seam: a 2^31-pixel row is rejected by CoreGraphics
            // without allocating it. The first cel is valid; the second cannot provide its pixels.
            let refused = VectorCanvas(size: CGSize(width: 2_147_483_648, height: 1),
                                       elements: [.fill(fixture.fills[1])])
            if failsInReference { manager.layers[0].cels[1].vector = refused }
            else { manager.layers[fixture.layer].cels[1].vector = refused }
            let baseline = steps(manager)

            let outcome = await manager.mendAllFills(layerIndex: fixture.layer)

            XCTAssertEqual(outcome, .needsMoreMemory, "unavailable pixels are not an empty successful input")
            for index in fixture.vectors.indices {
                XCTAssertEqual(fixture.vectors[index].elements.first?.fill?.pathData, fixture.fills[index].pathData,
                               "even a previously prepared cel stays unchanged")
            }
            XCTAssertEqual(refused.elements.first?.fill?.pathData, fixture.fills[1].pathData)
            XCTAssertEqual(steps(manager), baseline, "a failed whole-layer request records no partial undo")
            XCTAssertNil(manager.fillMendingLayerID)
        }
    }

    func testInteractiveFillRefusesUnavailableNeighbourPixelsAndCommitsNothing() async throws {
        _ = try XCTUnwrap(MetalFillEngine.shared)
        defer { VectorRenderCache.removeAll() }
        let (manager, layer, _) = vectorFixture()
        manager.setFillReference(layerIndex: layer, isReference: false)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(x: 4, y: 4, width: 8, height: 8), transform: nil),
                                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1))
        let refused = VectorCanvas(size: CGSize(width: 2_147_483_648, height: 1), elements: [.fill(fill)])
        manager.layers[layer].cels[0].vector = refused
        let baseline = steps(manager)

        manager.beginInteractiveFill(at: CGPoint(x: 32, y: 32))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        // The worker enqueues its refusal before returning. This barrier observes that callback
        // without waiting for the behavior under test, so a missing notice fails by assertion.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }

        XCTAssertEqual(manager.notice?.code, "fillNeedsMoreMemory", "unavailable neighbours must report the refusal")
        XCTAssertFalse(manager.fillGestureActive, "an unavailable neighbour ends the adjustable gesture")
        XCTAssertNil(manager.liveFill, "no preview can be mistaken for successful paint")
        manager.commitInteractiveFill()
        XCTAssertEqual(refused.elements.first?.fill?.pathData, fill.pathData)
        XCTAssertEqual(steps(manager), baseline, "the failed fill does not commit an undo step")
    }

    func testMendAllFillsLeavesRasterLayersAlone() async throws {
        let fixture = try mendFixture()
        let manager = fixture.manager
        // Raster cels can carry editable vector objects. Refusing an empty raster cel alone would
        // also pass if the vector-layer guard were removed, because there would be no fills to mend.
        manager.layers[fixture.layer].kind = .raster
        let baseline = steps(manager)
        let outcome = await manager.mendAllFills(layerIndex: fixture.layer)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(manager.layers[fixture.layer].kind, .raster)
        for index in fixture.vectors.indices {
            XCTAssertEqual(fixture.vectors[index].elements.first?.fill?.pathData, fixture.fills[index].pathData,
                           "the layer action leaves editable objects on raster cels unchanged")
        }
        XCTAssertEqual(steps(manager), baseline)
    }

    func testMendAllFillsKeepsOnePlanInFlightAndClearsItsBusyState() async throws {
        let fixture = try mendFixture()
        let manager = fixture.manager
        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        defer { gate.signal() }
        let started = expectation(description: "the batch exposes its busy state")
        let observation = manager.$fillMendingLayerID.compactMap { $0 }.prefix(1).sink { _ in started.fulfill() }
        defer { observation.cancel() }
        let operation = Task { await manager.mendAllFills(layerIndex: fixture.layer) }
        await fulfillment(of: [started], timeout: 5)
        let declined = expectation(description: "a duplicate returns without entering the blocked queue")
        let duplicate = Task {
            let outcome = await manager.mendAllFills(layerIndex: fixture.layer)
            declined.fulfill()
            return outcome
        }
        await fulfillment(of: [declined], timeout: 5)
        XCTAssertEqual(manager.fillMendingLayerID, manager.layers[fixture.layer].id)
        gate.signal()
        let outcome = await operation.value
        let duplicateOutcome = await duplicate.value
        XCTAssertEqual(duplicateOutcome, .superseded, "reopening the menu cannot retain another whole-layer plan")
        XCTAssertEqual(outcome, .changed(2), "the first request still completes")
        XCTAssertNil(manager.fillMendingLayerID, "the menu becomes available after completion")
    }

    func testMendAllFillsDiscardsPreparedGeometryWhenACanvasChangesDuringTheRequest() async throws {
        let fixture = try mendFixture()
        let manager = fixture.manager
        let baseline = steps(manager)
        let gate = DispatchSemaphore(value: 0)
        manager.fillQueue.async { gate.wait() }
        defer { gate.signal() }
        let started = expectation(description: "the batch has captured its original geometry")
        let observation = manager.$fillMendingLayerID.compactMap { $0 }.prefix(1).sink { _ in started.fulfill() }
        defer { observation.cancel() }
        let operation = Task { await manager.mendAllFills(layerIndex: fixture.layer) }
        await fulfillment(of: [started], timeout: 5)
        let edited = fixture.fills[0].reshaped(to: CGPath(rect: CGRect(x: 2, y: 2, width: 5, height: 5), transform: nil))
        fixture.vectors[0].restoreElements([.fill(edited)], changedInk: nil, rewriting: [edited.id])
        gate.signal()
        let outcome = await operation.value
        XCTAssertEqual(outcome, .superseded, "a captured version mismatch cancels the whole batch")
        XCTAssertEqual(fixture.vectors[0].elements.first?.fill?.pathData, edited.pathData,
                       "the artist's newer drawing is never overwritten")
        XCTAssertEqual(fixture.vectors[1].elements.first?.fill?.pathData, fixture.fills[1].pathData,
                       "the other cel does not receive a partial batch")
        XCTAssertEqual(steps(manager), baseline, "discarded work records no undo")
        XCTAssertNil(manager.fillMendingLayerID)
    }

    // MARK: - Reached only where it should be

    /// **Change Colour does not flatten a gradient**, and Opacity reaches it like any fill.
    func testChangeColourSkipsAGradientAndOpacityReachesIt() throws {
        let (manager, layerIndex, vector) = vectorFixture()
        let rect = CGRect(x: 10, y: 10, width: 40, height: 40)
        vector.addFill(path: CGPath(rect: rect, transform: nil),
                       paint: .linearGradient(.spanning(rect, angle: 0)))
        let before = try XCTUnwrap(vector.elements.first?.fill?.paint)
        let loop = CGPath(rect: CGRect(x: 2, y: 2, width: 60, height: 60), transform: nil)
        manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath)

        XCTAssertFalse(manager.applySelectionEdit(.color(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))),
                       "a hue written over both ends would flatten it, so Colour does not reach it")
        XCTAssertEqual(vector.elements.first?.fill?.paint, before)
        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.4)), "Opacity does")
        XCTAssertEqual(vector.elements.first?.fill?.opacity, 0.4)
    }
}
