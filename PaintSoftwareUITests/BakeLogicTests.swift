import XCTest
import UIKit

/// **Bake — TODO (131)**, against real documents: an effect, a flat colour or a transformation layer
/// carried into every drawing beneath it, and the layer removed.
///
/// *"there is the option to merge down effects layers with the layer below them. This is an incomplete
/// implementation. Instead, replace that buttons function with baking … it should adjust the color of all
/// the strokes/objects etc affected below it."* — owner.
///
/// **Three pins carry the feature, and everything else is what makes them honest.**
///
/// 1. *The colours changed.* Each stroke, fill, text and gradient stop beneath the layer holds the colour
///    the effect makes of it — asserted on the model, where a value is stored, **and** on the render,
///    where it is drawn: the baked document composites to what the layer made, byte for byte on crisp
///    ink (`testTheBakedDocumentRendersWhatTheEffectLayerMade`). A test that only read the model would
///    pass with the render path broken, which is how this repo's three unusable features shipped.
/// 2. *The compositor's own arithmetic.* The colour a bake writes comes out of `CoreGraphicsCompositor`,
///    so a raster layer baked into is byte-for-byte the pixels the compositor makes of the pair
///    (`testEveryGradeBakedIntoARasterLayerMakesWhatTheCompositorMakesOfIt`) — a second copy of the 25
///    modes or the grades anywhere on the path would part company with it.
/// 3. *What is left is said.* A layer a bake cannot honestly change is left exactly as it was and named.
///
/// `@MainActor` because `makeRenderRequest` is.
@MainActor
final class BakeLogicTests: XCTestCase {

    private let side = Int(CanvasFixture.canvasSize.width)
    private var whole: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    private var leftHalf: CGRect { CGRect(x: 0, y: 0, width: CGFloat(side) / 2, height: CGFloat(side)) }
    private var rightHalf: CGRect { CGRect(x: CGFloat(side) / 2, y: 0, width: CGFloat(side) / 2, height: CGFloat(side)) }

    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// +120° of hue, saturation and value untouched: red is exactly green and blue exactly red, so a
    /// test can state the colours a bake must produce as literals rather than as another run of the code.
    private static let hueRotate = Effect.hsvShift(Effect.HSVShift(hueDegrees: 120))

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func document() -> CanvasManager { CanvasFixture.manager(layerCount: 0) }

    private func index(_ id: UUID, _ manager: CanvasManager) -> Int {
        manager.layers.firstIndex { $0.id == id } ?? -1
    }

    /// A vector layer holding one flat rectangle per entry in its one cel — crisp, so a baked colour and
    /// a graded pixel are the same byte.
    @discardableResult
    private func addVector(_ manager: CanvasManager, _ name: String,
                           _ fills: [(CGRect, CodableColor)]) -> UUID {
        manager.addVectorLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        let vector = manager.layers[at].cels[0].vector!
        for (rect, colour) in fills {
            vector.addFill(canvasSpacePath: CGPath(rect: rect, transform: nil), color: colour)
        }
        return manager.layers[at].id
    }

    @discardableResult
    private func addRaster(_ manager: CanvasManager, _ name: String, _ colour: UIColor, _ rect: CGRect) -> UUID {
        manager.addLayer(name: name)
        let at = manager.layers.firstIndex { $0.name == name }!
        CanvasFixture.setBakedContent(manager, layerIndex: at, CanvasFixture.solidImage(colour, rect: rect))
        return manager.layers[at].id
    }

    @discardableResult
    private func addEffect(_ manager: CanvasManager, _ effect: Effect, name: String? = nil) -> UUID {
        manager.addValueLayer(effect: effect, name: name)
        return manager.layers[manager.currentLayerIndex].id
    }

    /// Every colour a vector layer's cel holds, in display order — strokes, flat fills and text.
    private func colours(of id: UUID, _ manager: CanvasManager, cel: Int = 0) -> [CodableColor] {
        guard let at = manager.layers.firstIndex(where: { $0.id == id }),
              let vector = manager.layers[at].cels[cel].vector else { return [] }
        return vector.elements.compactMap { element in
            switch element {
            case .stroke(let stroke): return stroke.composite == .paint ? stroke.color : nil
            case .fill(let fill): return fill.solidColor
            case .text(let text): return text.recipe.color
            case .image, .video, .stream: return nil
            }
        }
    }

    private func assertColour(_ colour: CodableColor?, _ r: Double, _ g: Double, _ b: Double,
                              _ message: String, accuracy: Double = 0.002,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let colour else { return XCTFail("\(message): no colour", file: file, line: line) }
        XCTAssertEqual(colour.red, r, accuracy: accuracy, "\(message) — red", file: file, line: line)
        XCTAssertEqual(colour.green, g, accuracy: accuracy, "\(message) — green", file: file, line: line)
        XCTAssertEqual(colour.blue, b, accuracy: accuracy, "\(message) — blue", file: file, line: line)
    }

    /// The document composited onto transparency — what the artist sees, less the paper.
    private func composite(_ manager: CanvasManager, frame: Int = 0) -> [UInt8]? {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        return manager.makeRenderRequest(atFrame: frame, includeBackground: false)
            .flatMap(Compositor.composite)
            .flatMap(CanvasFixture.rgbaBytes)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let offset = (x + y * side) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    private func bakePlan(_ outcome: CanvasManager.BakeOutcome) -> CanvasManager.BakePlan? {
        if case .baked(let plan) = outcome { return plan }
        return nil
    }

    // MARK: - (1) The colours change

    /// **The owner's own case, in the owner's own words:** *"2 layers and a blend mode value layer or
    /// effect layer above it. When that layer bakes, it should adjust the color of all the strokes/objects
    /// etc affected below it. In this case, it is both the layers below."*
    ///
    /// Red is `h = 0` and +120° is a third of a turn, so red is exactly green and blue — at 240° —
    /// exactly red. The layer is gone, both layers beneath are still vector layers, and nothing was
    /// asked: a bake that only rewrites colours in place runs at once.
    func testAnEffectLayerBakesIntoTheColourOfEveryDrawingBeneathIt() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(leftHalf, red)])
        let ink = addVector(manager, "Ink", [(rightHalf, blue)])
        let grade = addEffect(manager, Self.hueRotate)

        XCTAssertNotNil(manager.layers[index(grade, manager)].layerEffect, "Setup: the top layer grades")
        let outcome = manager.bakeLayer(id: grade)

        guard let plan = bakePlan(outcome) else { return XCTFail("Bake must run, got \(outcome)") }
        XCTAssertEqual(manager.layers.map(\.id), [floor, ink], "The effect layer is removed; both drawings stay")
        XCTAssertEqual(manager.layers.map(\.kind), [.vector, .vector], "…and stay vector layers, every stroke still a stroke")
        assertColour(colours(of: floor, manager).first, 0, 1, 0, "red under +120° of hue is green")
        assertColour(colours(of: ink, manager).first, 1, 0, 0, "blue under +120° of hue is red")
        XCTAssertEqual(plan.layers.count, 2, "Both layers beneath took it")
        XCTAssertTrue(plan.leftovers.isEmpty)
        XCTAssertFalse(plan.needsConfirmation, "Colours rewritten in place need no prompt")
        XCTAssertNil(manager.notice, "…and nothing was left, so nothing is said")
    }

    /// **The pin that would catch the model being right and the picture wrong.** Composited onto
    /// transparency, the document with the grade above it and the document with the grade baked in are
    /// the same bytes — crisp ink, so no antialiased edge is graded differently from a colour.
    func testTheBakedDocumentRendersWhatTheEffectLayerMade() {
        let manager = document()
        addVector(manager, "Floor", [(leftHalf, red)])
        addVector(manager, "Ink", [(rightHalf, blue)])
        let grade = addEffect(manager, Self.hueRotate)
        guard let before = composite(manager) else { return XCTFail("The document must composite") }
        XCTAssertEqual(pixel(before, side / 4, side / 2), [0, 255, 0, 255], "Premise: the grade turns red green on screen")

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))
        guard let after = composite(manager) else { return XCTFail("The baked document must composite") }

        XCTAssertEqual(after, before, "The baked picture is the picture the layer made")
        XCTAssertEqual(pixel(after, 3 * side / 4, side / 2), [255, 0, 0, 255], "…blue ink included")
    }

    /// A flat-colour value layer in Multiply — the owner's "blend mode value layer". Over white ink the
    /// product is the layer's own colour; over mid-grey, half of it.
    func testABlendValueLayerBakesItsBlendedColourIntoEveryDrawingBeneath() {
        let manager = document()
        let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
        let grey = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let floor = addVector(manager, "Floor", [(leftHalf, white)])
        let ink = addVector(manager, "Ink", [(rightHalf, grey)])
        manager.addValueLayer(color: PaletteColor(hex: "FF8000"), name: "Tint")
        let tint = manager.layers[manager.currentLayerIndex].id
        manager.layers[index(tint, manager)].blendMode = .multiply

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: tint)))

        assertColour(colours(of: floor, manager).first, 1, 128.0 / 255, 0, "white × orange is orange", accuracy: 0.005)
        assertColour(colours(of: ink, manager).first, 0.5, 0.25, 0, "grey × orange is half of it", accuracy: 0.006)
        XCTAssertEqual(manager.layers.count, 2, "The value layer is gone")
    }

    /// The layer's opacity is an amount, so half of a +120° rotation is the midpoint between red and
    /// green — not a half-transparent green. 255 → 0 and 0 → 255, each half way, is 128 on both.
    func testTheLayersOpacityCrossfadesTheColourItBakes() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(whole, red)])
        let grade = addEffect(manager, Self.hueRotate)
        manager.layers[index(grade, manager)].opacity = 0.5

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        assertColour(colours(of: floor, manager).first, 128.0 / 255, 128.0 / 255, 0,
                     "half way from red to green", accuracy: 0.005)
    }

    /// **A gradient bakes by mapping its stops**, and stays a gradient: the points, the angle and the
    /// Oklab ramp between them are untouched, so the middle is the colour a person would call halfway
    /// between the two *graded* stops.
    func testAGradientFillBakesThroughItsStopsAndStaysAGradient() {
        let manager = document()
        manager.addVectorLayer(name: "Sky")
        let sky = manager.layers[manager.currentLayerIndex].id
        let gradient = LinearGradientPaint(start: red, end: blue, from: .zero, to: CGPoint(x: 0, y: side))
        manager.layers[index(sky, manager)].cels[0].vector!
            .addFill(canvasSpacePath: CGPath(rect: whole, transform: nil), paint: .linearGradient(gradient))
        let grade = addEffect(manager, Self.hueRotate)

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        guard let fill = manager.layers[index(sky, manager)].cels[0].vector?.elements.first?.fill,
              let baked = fill.gradient else { return XCTFail("The fill must still be a gradient") }
        assertColour(baked.start, 0, 1, 0, "the red stop is green")
        assertColour(baked.end, 1, 0, 0, "the blue stop is red")
        XCTAssertEqual(baked.from, gradient.from, "Where the ramp starts is geometry, and geometry is untouched")
        XCTAssertEqual(baked.to, gradient.to)
    }

    /// Strokes, flat fills and text take the colour; **an eraser stroke has none and is left alone**
    /// (it is not "left as it was" in any way worth a notice — there was nothing there to change).
    func testStrokesAndTextTakeTheColourAndAnEraserStrokeDoesNot() {
        let manager = document()
        manager.addVectorLayer(name: "Ink")
        let ink = manager.layers[manager.currentLayerIndex].id
        let vector = manager.layers[index(ink, manager)].cels[0].vector!
        func stroke(_ colour: CodableColor, _ composite: StrokeComposite) -> VectorStroke {
            VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: colour, size: 4, opacity: 1,
                         samples: [VectorSample(x: 8, y: 20, pressure: 1), VectorSample(x: 40, y: 20, pressure: 1)],
                         composite: composite)
        }
        vector.addStroke(stroke(red, .paint))
        vector.addStroke(stroke(blue, .erase))
        var recipe = TextRecipe(string: "hi")
        recipe.color = red
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 8, y: 30), size: CGSize(width: 20, height: 12))))
        let grade = addEffect(manager, Self.hueRotate)

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        let elements = manager.layers[index(ink, manager)].cels[0].vector!.elements
        let strokes = elements.compactMap(\.stroke)
        assertColour(strokes.first { $0.composite == .paint }?.color, 0, 1, 0, "the painted stroke")
        assertColour(strokes.first { $0.composite == .erase }?.color, 0, 0, 1, "an eraser stroke carries no colour to take")
        assertColour(elements.compactMap(\.text).first?.recipe.color, 0, 1, 0, "the text")
    }

    /// **A placed image is graded into a new picture**, and the new picture carries no file name, so the
    /// next save writes it as an asset of its own and the original file is untouched until then.
    func testAPlacedImageIsGradedIntoANewPictureWithNoFileName() {
        let manager = document()
        manager.addVectorLayer(name: "Photo")
        let photo = manager.layers[manager.currentLayerIndex].id
        let picture = CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                               size: CGSize(width: 6, height: 6))
        var element = VectorImageElement(image: picture,
                                         transform: LayerTransform(position: CGPoint(x: 30, y: 30), scale: 1, rotation: 0))
        element.fileName = "photo.png"
        manager.layers[index(photo, manager)].cels[0].vector!.addImage(element)
        let grade = addEffect(manager, Self.hueRotate)

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        guard let baked = manager.layers[index(photo, manager)].cels[0].vector?.elements.first?.image,
              let cg = baked.image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else {
            return XCTFail("The image must survive the bake")
        }
        XCTAssertEqual(Array(bytes[0..<4]), [0, 255, 0, 255], "The picture's red is now green")
        XCTAssertNil(baked.fileName, "A new picture, so the next save writes a new asset")
        XCTAssertEqual(baked.image.size, picture.size, "…at the size it was placed at")
    }

    /// **A video and a stream have no colour to take and no asset to write one to**, so the operation
    /// says so rather than guessing — and the colour route is exhaustive over the element kinds, so a
    /// kind added later has to decide.
    func testAStreamCannotTakeAColourAndSaysSo() {
        let stream = VectorStreamElement(naturalSize: CGSize(width: 32, height: 18),
                                         host: "laptop", port: 47301, sourceLabel: "monitor",
                                         transform: LayerTransform(position: .zero, scale: 1, rotation: 0))
        let operation = BakeOperation.grade(Self.hueRotate, opacity: 1)

        guard case .cannotTakeColour = operation.baked(.stream(stream), using: BakedColours(operation)) else {
            return XCTFail("A live stream has no colour")
        }
    }

    // MARK: - One undo step

    /// **One step, and it brings the layer back whole.** The strokes are in cels the structure snapshot
    /// shares by reference, so a bake that rewrote a display list in place would leave the undo restoring
    /// a layer that still pointed at the baked ink — which is why this asserts the *colours* came back.
    func testBakingIsOneUndoStepThatBringsTheLayerAndTheOldColoursBack() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(leftHalf, red)])
        let grade = addEffect(manager, Self.hueRotate)
        let stepsBefore = manager.history.undoStack.count

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "One step, whatever it rewrote")
        XCTAssertEqual(manager.history.undoStack.last?.label, .bakeLayer)
        manager.undo()
        XCTAssertEqual(manager.layers.map(\.id), [floor, grade], "The effect layer is back")
        assertColour(colours(of: floor, manager).first, 1, 0, 0, "…and the drawing under it holds its own red again")
        manager.redo()
        XCTAssertEqual(manager.layers.map(\.id), [floor])
        assertColour(colours(of: floor, manager).first, 0, 1, 0, "Redo bakes it again")
    }

    // MARK: - (3) Scope and what is left

    /// **The adjustment layer's own scope rule: whatever is under it, within its group.** The layer
    /// above it and the layer outside the group are not touched.
    func testBakeReachesOnlyTheLayersBeneathItInItsOwnGroup() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(whole, red)])
        let inner = addVector(manager, "Inner", [(whole, red)])
        let grade = addEffect(manager, Self.hueRotate, name: "Grade")
        let above = addVector(manager, "Above", [(whole, red)])
        guard let folder = manager.groupLayers(grade, with: inner) else { return XCTFail("Setup: group") }
        manager.layers[index(above, manager)].parentFolderID = folder
        XCTAssertEqual(manager.layers.map(\.name), ["Floor", "Inner", "Grade", "Above"], "Setup: the folder holds the top three")

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        assertColour(colours(of: inner, manager).first, 0, 1, 0, "beneath it in its group: baked")
        assertColour(colours(of: above, manager).first, 1, 0, 0, "above it: untouched")
        assertColour(colours(of: floor, manager).first, 1, 0, 0, "outside its group: untouched")
    }

    /// A folder beneath the layer is part of what is beneath it, at any depth, and a hidden layer takes
    /// the bake too — it would take the effect the moment it was shown.
    func testBakeReachesIntoFoldersBeneathItAndIncludesHiddenLayers() {
        let manager = document()
        let deep = addVector(manager, "Deep", [(whole, red)])
        let shallow = addVector(manager, "Shallow", [(whole, red)])
        let hidden = addVector(manager, "Hidden", [(whole, red)])
        guard let folder = manager.groupLayers(deep, with: shallow) else { return XCTFail("Setup: group") }
        _ = folder
        manager.layers[index(hidden, manager)].isVisible = false
        let grade = addEffect(manager, Self.hueRotate)

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))

        assertColour(colours(of: deep, manager).first, 0, 1, 0, "inside the folder")
        assertColour(colours(of: shallow, manager).first, 0, 1, 0, "inside the folder")
        assertColour(colours(of: hidden, manager).first, 0, 1, 0, "hidden: it would be graded on being shown")
        XCTAssertFalse(manager.layers[index(hidden, manager)].isVisible, "…and it stays hidden")
    }

    /// **A mask makes the effect reach only part of a layer, and no colour stands for part of a drawing**
    /// — so it is left exactly as it was, the rest bakes, and the notice names it.
    func testALayerWithAMaskIsLeftAsItWasAndTheNoticeNamesIt() {
        let manager = document()
        let masked = addVector(manager, "Masked", [(whole, red)])
        let plain = addVector(manager, "Plain", [(whole, red)])
        manager.layers[index(masked, manager)].alphaMask = AlphaMask(sources: [.layer(plain)])
        let grade = addEffect(manager, Self.hueRotate)

        guard let plan = bakePlan(manager.bakeLayer(id: grade)) else { return XCTFail("The rest bakes") }

        assertColour(colours(of: plain, manager).first, 0, 1, 0, "the plain layer bakes")
        assertColour(colours(of: masked, manager).first, 1, 0, 0, "the masked one is left exactly as it was")
        XCTAssertEqual(plan.leftovers, [CanvasManager.BakeLeftover(name: "Masked", reason: .masked)])
        guard case .bakedWithLeftovers(let left)? = manager.notice?.kind else {
            return XCTFail("A notice must say what was left, got \(String(describing: manager.notice?.kind))")
        }
        XCTAssertEqual(left.map(\.name), ["Masked"])
        XCTAssertTrue(manager.notice?.message.contains("Masked") == true, "…and the sentence names it")
    }

    /// **Layers under another effect layer are left**: the order the two apply in could not be kept by
    /// baking into colours, so the artist is told which — and the answer is to bake the nearer one first.
    func testLayersUnderAnotherEffectLayerAreLeftAsTheyWereAndNamed() {
        let manager = document()
        let deep = addVector(manager, "Deep", [(whole, red)])
        let near = addEffect(manager, .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)), name: "Levelled")
        let mid = addVector(manager, "Mid", [(whole, red)])
        let grade = addEffect(manager, Self.hueRotate)

        guard let plan = bakePlan(manager.bakeLayer(id: grade)) else { return XCTFail("Mid bakes") }

        assertColour(colours(of: mid, manager).first, 0, 1, 0, "above the other effect: baked")
        assertColour(colours(of: deep, manager).first, 1, 0, 0, "under the other effect: left")
        XCTAssertEqual(plan.leftovers, [CanvasManager.BakeLeftover(name: "Deep", reason: .underAnotherEffect("Levelled"))])
        XCTAssertTrue(manager.layers.contains { $0.id == near }, "The other effect layer is not this bake's to touch")
    }

    func testBakeRefusesWhenItCannotHonestlyChangeAnything() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(whole, red)])
        let grade = addEffect(manager, Self.hueRotate)

        // A hidden layer changes nothing, so there is nothing to bake in.
        manager.layers[index(grade, manager)].isVisible = false
        XCTAssertEqual(manager.bakeLayer(id: grade), .refused(.hidden))
        manager.layers[index(grade, manager)].isVisible = true

        // A mask makes it reach only part of what is beneath.
        manager.layers[index(grade, manager)].alphaMask = AlphaMask(sources: [.layer(floor)])
        XCTAssertEqual(manager.bakeLayer(id: grade), .refused(.partialCoverage))
        manager.layers[index(grade, manager)].alphaMask = nil

        XCTAssertEqual(manager.bakeLayer(id: floor), .refused(.notABakingLayer), "A drawing layer is merged, not baked")
        XCTAssertEqual(manager.layers.count, 2, "A refusal keeps the layer, and says so")
        guard case .bakeRefused? = manager.notice?.kind else { return XCTFail("The refusal must raise a notice") }

        // A layer at the bottom has nothing beneath it.
        let alone = document()
        alone.addValueLayer(name: "Bottom")
        XCTAssertEqual(alone.bakeLayer(id: alone.layers[0].id), .refused(.nothingBeneath))
        XCTAssertEqual(alone.layers.count, 1)
    }

    // MARK: - (2) Pixels, through the compositor's own path

    /// **Every grade, baked into a raster layer, is the compositor's answer for that pair — byte for
    /// byte** — including the three effects that depend on position or neighbours and so could never be
    /// a colour (Glare, Lens Blur, Guide).
    func testEveryGradeBakedIntoARasterLayerMakesWhatTheCompositorMakesOfIt() {
        let grades: [Effect] = [
            Self.hueRotate,
            .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2, contrast: 1.5)),
            .hsvShift(Effect.HSVShift(hueDegrees: -40, saturation: 0.3, value: 1.4)),
            .posterize(Effect.Posterize(levels: 3)),
            .recolor(Effect.Recolor(entries: [
                RecolorEntry(from: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                             to: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                             tolerance: 0.2, softness: 0.5),
            ])),
            .colorWheels(Effect.ColorWheels(
                midtones: Effect.ColorWheels.Wheel(hue: 142, saturation: 0.8, luminance: 0.1),
                global: Effect.ColorWheels.Wheel(hue: 30, saturation: 0.3, luminance: 0.15, strength: 0.7))),
            .glare(Effect.Glare(type: .streaks, threshold: 0.2, intensity: 1, streaks: 2, length: 12)),
            .lensBlur(Effect.LensBlur(radius: 4, blades: 6, threshold: 0.2, boost: 3)),
            .guide(Effect.Guide(spacing: 8, lineWidth: 1, opacity: 0.7)),
            .blur(Effect.Blur(radius: 3)),
        ]
        for grade in grades {
            let manager = document()
            let floor = addRaster(manager, "Floor", .red, CGRect(x: 0, y: 0, width: CGFloat(side) * 0.75, height: CGFloat(side)))
            let layer = addEffect(manager, grade)
            guard let expected = composite(manager) else { return XCTFail("\(grade.displayName): must composite") }

            let outcome = manager.bakeLayer(id: layer)
            guard bakePlan(outcome) != nil, let at = manager.layers.firstIndex(where: { $0.id == floor }),
                  let image = PixelOps.rasterize(cel: manager.layers[at].cels[0],
                                                 canvasSize: CanvasFixture.canvasSize).cgImage,
                  let baked = CanvasFixture.rgbaBytes(image)
            else { return XCTFail("\(grade.displayName): must bake, got \(outcome)") }

            XCTAssertEqual(baked, expected, "\(grade.displayName): the baked pixels are the compositor's own")
        }
    }

    /// **Every blend mode a flat-colour layer can have, baked into a raster layer, matches the
    /// compositor inside the ink — and the layer's gaps stay gaps.** Over transparency the compositor
    /// shows the sheet itself (a blend against nothing is its source), which is the paper's business;
    /// Bake changes the drawings only, so where the layer drew nothing it still draws nothing.
    func testEveryBlendModeBakedIntoARasterLayerMatchesTheCompositorInsideTheInk() {
        for mode in BlendMode.allCases where mode != .clipToBelow {
            let manager = document()
            let floor = addRaster(manager, "Floor", UIColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1), leftHalf)
            manager.addValueLayer(color: PaletteColor(hex: "3366CC"), name: "Tint")
            let tint = manager.layers[manager.currentLayerIndex].id
            manager.layers[index(tint, manager)].blendMode = mode
            guard let expected = composite(manager) else { return XCTFail("\(mode.displayName): must composite") }

            XCTAssertNotNil(bakePlan(manager.bakeLayer(id: tint)), "\(mode.displayName): must bake")
            guard let at = manager.layers.firstIndex(where: { $0.id == floor }),
                  let image = PixelOps.rasterize(cel: manager.layers[at].cels[0],
                                                 canvasSize: CanvasFixture.canvasSize).cgImage,
                  let baked = CanvasFixture.rgbaBytes(image)
            else { return XCTFail("\(mode.displayName): must read back") }

            XCTAssertEqual(pixel(baked, side / 4, side / 2), pixel(expected, side / 4, side / 2),
                           "\(mode.displayName): inside the ink the compositor and the bake agree")
            XCTAssertEqual(pixel(baked, 3 * side / 4, side / 2), [0, 0, 0, 0],
                           "\(mode.displayName): where the layer drew nothing it still draws nothing")
        }
    }

    /// **An effect that works on pixels turns each affected vector layer into a raster layer, after a
    /// prompt that says so** — and until the artist answers, nothing has changed.
    func testAnEffectThatNeedsPixelsTurnsAVectorLayerIntoARasterLayerAfterAPrompt() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(leftHalf, red)])
        let blur = addEffect(manager, .blur(Effect.Blur(radius: 3)))
        guard let before = composite(manager) else { return XCTFail("The document must composite") }

        manager.requestBake(layerID: blur)

        XCTAssertNotNil(manager.pendingBake, "A bake that changes what a layer *is* asks first")
        XCTAssertTrue(manager.pendingBake?.message.contains("Floor") == true, "…and names the layer it turns into pixels")
        XCTAssertTrue(manager.pendingBake?.message.contains("raster layer") == true)
        XCTAssertEqual(manager.layers.map(\.kind), [.vector, .value], "Nothing changed yet")

        manager.cancelPendingBake()
        XCTAssertEqual(manager.layers.count, 2, "Cancel means cancel")

        manager.requestBake(layerID: blur)
        manager.confirmPendingBake()

        XCTAssertNil(manager.pendingBake)
        XCTAssertEqual(manager.layers.map(\.id), [floor])
        XCTAssertEqual(manager.layers[0].kind, .raster, "Painted into the pixels, so a raster layer now")
        XCTAssertNil(manager.layers[0].cels[0].vector, "…its strokes are gone with the kind")
        guard let after = composite(manager) else { return XCTFail("The baked document must composite") }
        XCTAssertEqual(after, before, "The raster layer shows the blurred picture the effect layer made")
    }

    /// **A drawing animated by pose channels takes a colour effect and keeps its animation** — the
    /// colours are in the strokes, the channel is untouched — **and is left alone by an effect that
    /// needs pixels**, because painting it would flatten the motion to the frame the cel starts on.
    func testAnAnimatedDrawingKeepsItsAnimationThroughAColourBakeAndIsLeftByAPixelsOne() {
        func animated() -> (CanvasManager, UUID) {
            let manager = document()
            let floor = addVector(manager, "Floor", [(leftHalf, red)])
            let rest = PoseQuad(restingIn: whole)
            let moved = PoseQuad(box: whole, mappedBy: CGAffineTransform(translationX: 8, y: 0))
            manager.layers[index(floor, manager)].cels[0].transformTracks = [
                TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, rest), (11, moved)], interpolation: .linear)]
            return (manager, floor)
        }

        let (colour, floor) = animated()
        let grade = addEffect(colour, Self.hueRotate)
        XCTAssertNotNil(bakePlan(colour.bakeLayer(id: grade)))
        assertColour(colours(of: floor, colour).first, 0, 1, 0, "the colour is in the stroke")
        XCTAssertFalse(colour.layers[index(floor, colour)].cels[0].transformTracks.isEmpty, "…and the animation is untouched")

        let (pixels, drawing) = animated()
        let blur = addEffect(pixels, .blur(Effect.Blur(radius: 3)))
        XCTAssertEqual(pixels.bakeLayer(id: blur),
                       .refused(.nothingToBake([CanvasManager.BakeLeftover(name: "Floor", reason: .animatedDrawing)])))
        XCTAssertEqual(pixels.layers[index(drawing, pixels)].kind, .vector, "Left exactly as it was")
    }

    /// **`Effect.bakeRoute` is exhaustive, and the property the owner's ruling rests on holds for every
    /// case**: whatever `reshapesCoverage` names is a pixels effect, and a colour effect is a function
    /// of colour alone — the same colour at two positions comes out the same.
    func testTheRouteOfEveryEffectAgreesWithWhatItDoes() {
        let every: [Effect] = [
            .levels(Effect.Levels(inputBlack: 0.1, inputWhite: 0.9, gamma: 1.4)),
            .curves(Effect.Curves()),
            .brightnessContrast(Effect.BrightnessContrast(brightness: 1.3, contrast: 1.4)),
            .hsvShift(Effect.HSVShift(hueDegrees: 44, saturation: 1.3, value: 0.9)),
            .gradientMap(Effect.GradientMap(mix: 1)),
            .chromaticAberration(Effect.ChromaticAberration(offsetX: 2, offsetY: 1)),
            .posterize(Effect.Posterize(levels: 3)),
            .posterize(Effect.Posterize(levels: 3, screen: .ordered, screenStrength: 1)),
            .noise(Effect.Noise(amount: 0.4, seed: 3)),
            .blur(Effect.Blur(radius: 4)),
            .bloom(Effect.Bloom(threshold: 0.4, radius: 5, intensity: 0.9)),
            .sobel(Effect.Sobel()),
            .sharpen(Effect.Sharpen(radius: 3, amount: 1)),
            .outline(Effect.Outline()),
            .recolor(Effect.Recolor(entries: [])),
            .crtScreen(Effect.CRTScreen()),
            .duplicateOffset(Effect.DuplicateOffset()),
            .glare(Effect.Glare(type: .streaks, threshold: 0.2, intensity: 1, streaks: 2, length: 12)),
            .colorWheels(Effect.ColorWheels()),
            .lensBlur(Effect.LensBlur(radius: 4, blades: 6, threshold: 0.2, boost: 3)),
            .guide(Effect.Guide(spacing: 8, lineWidth: 1, opacity: 0.7)),
        ]
        for effect in every {
            // Exhaustive on purpose: an effect added later makes this stop compiling until it is told
            // which route it is expected to take.
            let expected: Effect.BakeRoute
            switch effect {
            case .levels, .curves, .brightnessContrast, .hsvShift, .gradientMap, .recolor, .colorWheels: expected = .colour
            case .posterize(let posterize): expected = posterize.screen == .none ? .colour : .pixels
            case .chromaticAberration, .noise, .blur, .bloom, .sobel, .sharpen, .outline, .crtScreen,
                 .duplicateOffset, .glare, .lensBlur, .guide: expected = .pixels
            }
            XCTAssertEqual(effect.bakeRoute, expected, "\(effect.displayName)")
            if effect.reshapesCoverage {
                XCTAssertEqual(effect.bakeRoute, .pixels, "\(effect.displayName) reshapes coverage, so it cannot be a colour")
            }
        }
        // And the colour route really is a function of colour: the same pixel at two positions.
        for effect in every where effect.bakeRoute == .colour {
            var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
            for pixel in 0..<64 {
                bytes[pixel * 4] = 200; bytes[pixel * 4 + 1] = 60; bytes[pixel * 4 + 2] = 90; bytes[pixel * 4 + 3] = 255
            }
            let out = EffectReference.apply(effect, to: bytes, width: 8, height: 8)
            XCTAssertEqual(Array(out[0..<4]), Array(out[(8 * 4 + 5) * 4..<(8 * 4 + 5) * 4 + 4]),
                           "\(effect.displayName) is declared a colour effect, so position cannot matter")
        }
    }

    // MARK: - Animation

    /// **One drawing per frame where the result changes** — Bake Animation's rule — and the prompt says
    /// how many and what every save then costs, before anything is written.
    func testAnAnimatedEffectBakesOneDrawingPerDistinctFrameAndThePromptSaysSo() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(whole, red)])
        manager.layers[index(floor, manager)].cels[0].frameCount = 4
        let grade = addEffect(manager, Effect.hsvShift(Effect.HSVShift(hueDegrees: 0)))
        manager.layers[index(grade, manager)].cels[0].frameCount = 4
        manager.layers[index(grade, manager)].effectTracks = ["hsvShift.hue": AnimationCurve(keys: [
            .init(frame: 0, value: 0, interpolation: .linear),
            .init(frame: 3, value: 120, interpolation: .linear)])]

        guard case .plan(let plan) = manager.bakePlan(forLayerID: grade) else { return XCTFail("Must plan") }
        XCTAssertEqual(plan.addedCels.vector, 3, "Four distinct frames from one cel: three more drawings")
        XCTAssertTrue(plan.needsConfirmation, "Added drawings cost every future save, so the artist is asked")
        XCTAssertTrue(plan.confirmationMessage.contains("3 drawings"), plan.confirmationMessage)
        XCTAssertTrue(plan.confirmationMessage.contains("save"), "…and what every save costs: \(plan.confirmationMessage)")
        XCTAssertEqual(manager.layers[index(floor, manager)].cels.count, 1, "Planning wrote nothing")

        manager.requestBake(layerID: grade)
        XCTAssertNotNil(manager.pendingBake)
        manager.confirmPendingBake()

        let cels = manager.layers[index(floor, manager)].cels
        XCTAssertEqual(cels.map(\.startFrame), [0, 1, 2, 3], "One cel a frame")
        let baked = cels.indices.compactMap { colours(of: floor, manager, cel: $0).first }
        assertColour(baked.first, 1, 0, 0, "Frame 0: the grade is at rest, so red")
        assertColour(baked.last, 0, 1, 0, "Frame 3: a third of a turn, so green")
        let distinct = Set(baked.map { String(format: "%.3f,%.3f", $0.red, $0.green) })
        XCTAssertEqual(distinct.count, 4, "Every frame is its own colour, so every frame is its own drawing: \(distinct)")
    }

    /// **The sentence's numbers come out of the plan, each at its own kind's measured rate** — a vector
    /// cel is a display list (2.4 ms a save) and a raster cel a canvas-sized picture (15.2 ms), so three
    /// of the first and one of the second cost 3 × 2.4 + 15.2 = 22.4 ms, and the layer that becomes
    /// pixels is named.
    func testTheConfirmationSentenceIsComputedFromThePlanAtEachKindsOwnRate() {
        let first = BakeOperation.grade(Self.hueRotate, opacity: 1)
        let second = BakeOperation.grade(Self.hueRotate, opacity: 0.5)
        func cuts(_ runs: Int) -> CanvasManager.CelBake {
            CanvasManager.CelBake(celID: UUID(), segments: (0..<runs).map {
                CanvasManager.BakeSegment(localStart: $0, length: 1,
                                          treatment: .operation($0 % 2 == 0 ? first : second))
            })
        }
        let plan = CanvasManager.BakePlan(
            bakerID: UUID(), bakerName: "Grade",
            layers: [CanvasManager.LayerBake(layerID: UUID(), name: "Ink", medium: .ink, cels: [cuts(4)]),
                     CanvasManager.LayerBake(layerID: UUID(), name: "Sky", medium: .pixels(rasterizes: true), cels: [cuts(2)])],
            leftovers: [])

        XCTAssertEqual(plan.addedCels.vector, 3)
        XCTAssertEqual(plan.addedCels.raster, 1)
        XCTAssertTrue(plan.needsConfirmation)
        let message = plan.confirmationMessage
        XCTAssertTrue(message.contains("Sky will become a raster layer"), message)
        XCTAssertFalse(message.contains("Ink will become"), "A layer that stays strokes is not announced as pixels: \(message)")
        XCTAssertTrue(message.contains("adds 4 drawings"), message)
        XCTAssertTrue(message.contains("about 22 ms longer"), message)
        XCTAssertTrue(message.contains("Grade is removed. This can be undone."), message)
    }

    /// **A grade that holds across the whole cel is one drawing.** The same layer, the same cel, a static
    /// effect: no cut, no prompt.
    func testAStaticEffectAcrossTheWholeCelStaysOneDrawing() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(whole, red)])
        let grade = addEffect(manager, Self.hueRotate)

        guard case .plan(let plan) = manager.bakePlan(forLayerID: grade) else { return XCTFail("Must plan") }
        XCTAssertEqual(plan.addedCels.vector + plan.addedCels.raster, 0)

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))
        XCTAssertEqual(manager.layers[index(floor, manager)].cels.count, 1)
    }

    /// **A bar that covers only part of a cel cuts the cel at the bar's edges**, and the drawings the bar
    /// does not reach are left as they were — the paper-white rule's twin in time: Bake changes the
    /// frames the layer acted on and no others.
    func testABarCoveringPartOfACelCutsTheCelAtTheBarsEdgesAndLeavesTheRestAlone() {
        let manager = document()
        let floor = addVector(manager, "Floor", [(whole, red)])
        let grade = addEffect(manager, Self.hueRotate)
        manager.layers[index(grade, manager)].cels[0].startFrame = 4
        manager.layers[index(grade, manager)].cels[0].frameCount = 4
        XCTAssertEqual(manager.layers[index(floor, manager)].cels[0].frameCount, 12, "Setup: the drawing spans the scene")

        manager.requestBake(layerID: grade)
        XCTAssertNotNil(manager.pendingBake, "Two cuts add two drawings")
        manager.confirmPendingBake()

        let cels = manager.layers[index(floor, manager)].cels
        XCTAssertEqual(cels.map(\.startFrame), [0, 4, 8])
        XCTAssertEqual(cels.map(\.frameCount), [4, 4, 4])
        assertColour(colours(of: floor, manager, cel: 0).first, 1, 0, 0, "before the bar: as it was")
        assertColour(colours(of: floor, manager, cel: 1).first, 0, 1, 0, "under the bar: graded")
        assertColour(colours(of: floor, manager, cel: 2).first, 1, 0, 0, "after the bar: as it was")
    }

    /// A flat-colour layer has no frames of its own to cut, so it takes the bake only where the baking
    /// layer covers all of it the same way — and is left, and named, where it covers part.
    func testAFlatColourLayerBeneathTakesAStaticBakeAndIsLeftWhenOnlyPartlyCovered() {
        let manager = document()
        manager.addValueLayer(color: PaletteColor(hex: "FF0000"), name: "Background")
        let background = manager.layers[manager.currentLayerIndex].id
        let grade = addEffect(manager, Self.hueRotate)

        XCTAssertNotNil(bakePlan(manager.bakeLayer(id: grade)))
        XCTAssertEqual(manager.layers[index(background, manager)].fill?.color.hex, "00FF00", "Red grades to green")

        let alone = document()
        alone.addValueLayer(color: PaletteColor(hex: "FF0000"), name: "Partly")
        let partly = alone.layers[alone.currentLayerIndex].id
        let half = addEffect(alone, Self.hueRotate)
        alone.layers[index(half, alone)].cels[0].frameCount = 6

        guard case .refused(.nothingToBake(let left)) = alone.bakeLayer(id: half) else {
            return XCTFail("The only layer beneath is only partly covered")
        }
        XCTAssertEqual(left, [CanvasManager.BakeLeftover(name: "Partly", reason: .partlyCovered)])
        XCTAssertEqual(alone.layers[index(partly, alone)].fill?.color.hex, "FF0000", "…and it is exactly as it was")
    }
}
