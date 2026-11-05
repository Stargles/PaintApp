import XCTest
import SwiftUI

/// **TODO (42) — Colour, Size and Opacity on a selection, live, as one undo step.** The session in
/// `CanvasManager+SelectionEdit.swift`: `beginSelectionEdit` resolves the loop, `previewSelectionEdit`
/// holds the caught elements' rewritten list on every tick, `commitSelectionEdit` writes it once and
/// records the one step, `cancelSelectionEdit` lets the held list go.
///
/// Stored-field tests pin the edit arithmetic; the pose regressions also inspect actual compositor
/// pixels. `SelectionEditUITests` drives a fresh document off the screen — and, for the held
/// window's own picture, `LiveElementEditLogicTests`'. What these pin is the arithmetic a drag has to
/// get right whatever the picture looks like — which ids a tick may touch, what "one step" means
/// across ten ticks, what a cancel leaves, and which kinds each control reaches. **Mid-drag the
/// document is not the thing to read** (TODO (173)): a tick is held off it, so `shown` is — the live
/// edit's list while one is up. The mutation each test caught is in its doc comment.
final class SelectionEditLogicTests: XCTestCase {

    // MARK: - Fixtures (`LassoMoveLogicTests`' shape)

    private func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CodableColor {
        CodableColor(red: r, green: g, blue: b, alpha: a)
    }

    /// A manager with a raster layer at 0 and an **active vector layer at 1**.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    /// A horizontal three-sample stroke at `y`, from x = 10 to x = 54 — well inside a 64-point canvas.
    private func stroke(y: CGFloat, size: CGFloat = 4, opacity: Double = 1,
                        colour: CodableColor? = nil, composite: StrokeComposite = .paint,
                        from x0: CGFloat = 10, to x1: CGFloat = 54) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: colour ?? self.colour(0, 0, 0),
                     size: size, opacity: opacity,
                     samples: [VectorSample(x: x0, y: y, pressure: 1),
                               VectorSample(x: (x0 + x1) / 2, y: y, pressure: 1),
                               VectorSample(x: x1, y: y, pressure: 1)],
                     composite: composite)
    }

    private func loop(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ path: CGPath) {
        manager.selection = Selection(path: path, bounds: path.boundingBoxOfPath)
    }

    /// Undo steps recorded since the fixture was built — `LassoMoveLogicTests.stepsSince`'s reason:
    /// `fixture()` records two structural steps of its own.
    private func stepsSince(_ baseline: Int, _ manager: CanvasManager) -> Int {
        manager.history.undoStack.count - baseline
    }

    private func sizes(_ vector: VectorCanvas) -> [CGFloat] { vector.elements.compactMap { $0.stroke?.size } }
    /// What the canvas shows of the cel mid-drag: the live edit's list while one is held, the
    /// document's otherwise. A tick is not a document write (TODO (173)), so mid-drag the document
    /// still says what it said before the finger went down.
    private func shown(_ manager: CanvasManager, _ vector: VectorCanvas) -> [VectorElement] {
        manager.liveCelContentEdit?.elements ?? vector.elements
    }
    private func shownSizes(_ manager: CanvasManager, _ vector: VectorCanvas) -> [CGFloat] {
        shown(manager, vector).compactMap { $0.stroke?.size }
    }
    private func opacities(_ vector: VectorCanvas) -> [Double] { vector.elements.compactMap { $0.stroke?.opacity } }

    /// Three strokes at y = 10, 20 and 50, sizes 4, 6 and 8; a loop that catches the first two whole.
    private func threeStrokes() -> (CanvasManager, Int, VectorCanvas, Set<UUID>, UUID) {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 10, size: 4, opacity: 0.4))
        vector.addStroke(stroke(y: 20, size: 6, opacity: 0.6))
        vector.addStroke(stroke(y: 50, size: 8, opacity: 0.8))
        let caught = Set(vector.elements.prefix(2).map(\.id))
        let outside = vector.elements[2].id
        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 28)))
        return (manager, layerIndex, vector, caught, outside)
    }

    // MARK: - Scope: only the selected ids

    /// **Each control rewrites only what the loop caught.** Two strokes inside, one outside; after each
    /// one-shot the two carry the value and the third carries what it had.
    ///
    /// Mutation caught: dropping `session.caught.contains(element.id)` from `previewSelectionEdit`'s
    /// loop rewrites every element in the cel — the third stroke takes the value and all three
    /// assertions on it go red.
    func testColourSizeAndOpacityEachRewriteOnlyTheSelectedIds() {
        let (manager, _, vector, caught, outside) = threeStrokes()
        let baseline = manager.history.undoStack.count

        XCTAssertTrue(manager.applySelectionEdit(.color(colour(1, 0, 0))), "the recolour changed something")
        for element in vector.elements {
            let stroke = element.stroke!
            if caught.contains(stroke.id) {
                XCTAssertEqual(stroke.color, colour(1, 0, 0), "a caught stroke takes the colour")
            } else {
                XCTAssertEqual(stroke.id, outside)
                XCTAssertEqual(stroke.color, colour(0, 0, 0), "the stroke outside the loop keeps its colour")
            }
        }

        XCTAssertTrue(manager.applySelectionEdit(.size(12)))
        XCTAssertEqual(sizes(vector), [12, 12, 8], "size reaches the two caught strokes and not the third")

        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.25)))
        XCTAssertEqual(opacities(vector), [0.25, 0.25, 0.8], "opacity reaches the two and not the third")

        XCTAssertEqual(stepsSince(baseline, manager), 3, "three one-shots, three steps")
    }

    /// The loop and frame stay fixed while graph/pose writers carry another mark into it. Pose
    /// tracks do not rewrite stored ink, so both memo readouts must include their resolved inputs.
    @MainActor
    func testSelectionReadoutsFollowSameFrameCelGroupAndContainerPoseEdits() throws {
        let previousBackend = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previousBackend }
        for owner in ["cel", "group", "container"] {
            let (manager, layer, vector) = fixture()
            let red = colour(1, 0, 0), blue = colour(0, 0, 1), green = colour(0, 1, 0)
            let a = UUID(), b = UUID()
            manager.animationGroups = [AnimationGroup(id: a, displayName: "Red group", tagColor: red),
                                       AnimationGroup(id: b, displayName: "Blue group", tagColor: blue)]
            var left = stroke(y: 20, size: 4, colour: red, from: 10, to: 20)
            var right = stroke(y: 20, size: 8, opacity: 0.5, colour: blue, from: 42, to: 52)
            left.animationGroupID = a
            right.animationGroupID = b
            vector.addStroke(left)
            vector.addStroke(right)
            let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
            let channels: [TransformChannelID] = owner == "group" ? [.group(a), .group(b)] : [.cel]
            if owner == "container" {
                manager.addTransformLayer()
                manager.currentLayerIndex = layer
            } else {
                for channel in channels {
                    manager.layers[layer].cels[0].transformTracks[channel.id] = TransformTrack(box: box,
                        curves: [.x: AnimationCurve(keys: [.init(frame: 0, value: 32)])])
                }
            }
            let path = loop(CGRect(x: 6, y: 10, width: 22, height: 24))
            select(manager, layer, path)
            manager.selectionMembership = .touching
            for _ in 0..<3 {
                XCTAssertEqual(manager.selectionStyle.color, red, "warm the ordinary pose's style memo")
                XCTAssertEqual(manager.selectionAnimationGroupName, "Red group", "warm the group memo too")
            }
            let oldPixel = try memoPixel(manager, at: CGPoint(x: 15, y: 20))
            XCTAssertGreaterThan(oldPixel[0], 200)
            XCTAssertLessThan(oldPixel[2], 30)
            let version = vector.version
            let frame = manager.currentFrame
            let steps = manager.history.undoStack.count
            if owner == "container" {
                let target = KeyframeTarget.layer(id: manager.layers[layer + 1].id)
                let before = manager.layers[layer + 1].transform
                manager.writeContainerPose(LayerPose(pose: PoseQuad(box: box,
                    mappedBy: CGAffineTransform(translationX: -32, y: 0)), mode: .move), from: before, target: target)
            } else {
                let changes = Dictionary(uniqueKeysWithValues: channels.map {
                    (PoseChannelID.cel($0).parameterID(.x), Optional(AnimationCurve(keys: [.init(frame: 0, value: 0)])))
                })
                XCTAssertTrue(manager.setPoseChannelTracks(.layer(id: manager.layers[layer].id), curves: changes))
            }
            XCTAssertEqual(manager.currentFrame, frame)
            XCTAssertTrue(manager.selection?.path === path)
            XCTAssertEqual(vector.version, version, "PREMISE: only resolved pose changed, not stored ink")
            let newPixel = try memoPixel(manager, at: CGPoint(x: 15, y: 20))
            XCTAssertGreaterThan(newPixel[2], 100, "blue is now drawn inside the fixed loop")
            XCTAssertLessThan(newPixel[0], 30)
            for _ in 0..<3 {
                let style = manager.selectionStyle
                XCTAssertEqual(style.color, blue)
                XCTAssertEqual(style.size, 8)
                XCTAssertEqual(style.opacity, 0.5)
                XCTAssertFalse(style.colorIsMixed)
                XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group")
            }
            XCTAssertEqual(manager.history.undoStack.count, steps + 1)
            XCTAssertTrue(manager.applySelectionEdit(.color(green)), "the action reaches the mark the readout now names")
            XCTAssertEqual(vector.elements.first(where: { $0.id == left.id })?.stroke?.color, red)
            XCTAssertEqual(vector.elements.first(where: { $0.id == right.id })?.stroke?.color, green)
            let editedPixel = try memoPixel(manager, at: CGPoint(x: 15, y: 20))
            XCTAssertGreaterThan(editedPixel[1], 100)
            XCTAssertLessThan(editedPixel[0], 30)
            manager.undo()
            XCTAssertEqual(manager.selectionStyle.color, blue)
            manager.undo()
            XCTAssertEqual(manager.selectionStyle.color, red)
            XCTAssertEqual(manager.selectionAnimationGroupName, "Red group")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 20)), oldPixel)
            manager.redo()
            XCTAssertEqual(manager.selectionStyle.color, blue)
            XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 20)), newPixel)
        }
    }

    @MainActor
    func testSelectionTextEditorFollowsTheNewObjectAfterASameFramePoseEdit() throws {
        let (manager, layer, vector) = fixture()
        var red = TextRecipe(string: "LEFT")
        red.color = colour(1, 0, 0)
        var blue = TextRecipe(string: "RIGHT")
        blue.color = colour(0, 0, 1)
        let left = VectorTextElement(recipe: red, frame: TextFrame(origin: CGPoint(x: 10, y: 16), size: CGSize(width: 16, height: 18)))
        let right = VectorTextElement(recipe: blue, frame: TextFrame(origin: CGPoint(x: 42, y: 16), size: CGSize(width: 16, height: 18)))
        vector.upsertText(left)
        vector.upsertText(right)
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        manager.layers[layer].cels[0].transformTracks[TransformChannelID.cel.id] = TransformTrack(box: box,
            curves: [.x: AnimationCurve(keys: [.init(frame: 0, value: 32)])])
        select(manager, layer, loop(CGRect(x: 6, y: 10, width: 24, height: 30)))
        manager.selectionMembership = .touching
        XCTAssertEqual(manager.selectionStyle.editableObjects[.text], left.id, "warm the text editor target")
        let version = vector.version
        XCTAssertTrue(manager.setPoseChannelTrack(.layer(id: manager.layers[layer].id),
            parameterID: PoseChannelID.cel(.cel).parameterID(.x), to: AnimationCurve(keys: [.init(frame: 0, value: 0)])))
        XCTAssertEqual(vector.version, version)
        XCTAssertEqual(manager.selectionStyle.editableObjects[.text], right.id)
        XCTAssertTrue(manager.editSelectedObject(.text))
        XCTAssertEqual(manager.textEditingElementID, right.id, "Edit opens the object now inside the loop")
        XCTAssertEqual(manager.textRecipe.string, "RIGHT")
        manager.cancelInteractiveText()
    }

    @MainActor
    private func memoPixel(_ manager: CanvasManager, at point: CGPoint) throws -> [UInt8] {
        let image = try memoPicture(manager)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(image))
        let offset = (Int(point.y) * image.width + Int(point.x)) * 4
        return Array(bytes[offset..<(offset + 4)])
    }

    @MainActor
    private func memoPicture(_ manager: CanvasManager) throws -> CGImage {
        try XCTUnwrap(manager.makeRenderRequest(atFrame: manager.currentFrame, includeBackground: false)
            .flatMap(Compositor.composite))
    }

    /// The source drawing is read at 2 while its parent above Repeat is read at 14. The blue mark
    /// moves 32 pt left through its cel and 8 pt down through its group, then another 8 through the
    /// document-time parent. Reading either time incorrectly therefore catches another mark or paper.
    private func repeatedSelectionFixture(sourceOnly: Bool) throws
        -> (manager: CanvasManager, vector: VectorCanvas, red: UUID, blue: UUID, redGroup: UUID, blueGroup: UUID) {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = CanvasFixture.canvasSize
        manager.addVectorLayer(name: "Source ink")
        manager.addTransformLayer(name: "Repeat")
        manager.addTransformLayer(name: "Outer Move")
        manager.layers[0].cels[0].frameCount = sourceOnly ? 3 : 24
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 24)])
        CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 24)])
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 12)
        manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: box),
            track: CanvasFixture.poseTrack([
                (2, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: -8))),
                (14, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: 8)))
            ], interpolation: .linear))
        let a = AnimationGroup(displayName: "Red group", tagColor: colour(1, 0, 0))
        let b = AnimationGroup(displayName: "Blue group", tagColor: colour(0, 0, 1))
        manager.animationGroups = [a, b]
        let vector = try XCTUnwrap(manager.layers[0].cels[0].vector)
        var red = stroke(y: 20, size: 4, colour: colour(1, 0, 0), from: 10, to: 20)
        var blue = stroke(y: 20, size: 8, opacity: 0.5, colour: colour(0, 0, 1), from: 42, to: 52)
        red.animationGroupID = a.id
        blue.animationGroupID = b.id
        vector.addStroke(red)
        vector.addStroke(blue)
        let last = sourceOnly ? 2 : 14
        let xKeys: [AnimationCurve.Key] = sourceOnly ? [.init(frame: 2, value: 0)]
            : [.init(frame: 2, value: 0), .init(frame: last, value: 32)]
        let yKeys: [AnimationCurve.Key] = sourceOnly ? [.init(frame: 2, value: 40)]
            : [.init(frame: 2, value: 40), .init(frame: last, value: 32)]
        manager.layers[0].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(box: box, curves: [.x: AnimationCurve(keys: xKeys)]),
            TransformChannelID.group(b.id).id: TransformTrack(box: box, curves: [.y: AnimationCurve(keys: yKeys)])
        ]
        manager.currentLayerIndex = 0
        manager.currentFrame = 14
        select(manager, 0, loop(CGRect(x: 6, y: 26, width: 22, height: 20)))
        manager.selectionMembership = .touching
        manager.history.removeAll()
        return (manager, vector, red.id, blue.id, a.id, b.id)
    }

    private func selectionInk(_ vector: VectorCanvas) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(VectorCanvasData(from: vector, imageFileNames: [:]))
    }

    @MainActor
    func testRepeatedCutMoveRetakesFreshPiecePosesAtSourceTimeAndDocumentParent() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            f.vector.elements = []
            f.vector.addFill(path: loop(CGRect(x: 42, y: 20, width: 10, height: 8)), color: colour(0, 0, 1))
            let originalID = try XCTUnwrap(f.vector.elements.first?.id)
            manager.layers[0].cels[0].transformTracks.removeValue(forKey: TransformChannelID.group(f.blueGroup).id)
            if !sourceOnly {
                manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id] = TransformTrack(
                    box: CGRect(origin: .zero, size: CanvasFixture.canvasSize), curves: [.x: AnimationCurve(keys: [
                        .init(frame: 2, value: 0), .init(frame: 3, value: 32)])])
            }
            select(manager, 0, loop(CGRect(x: 15, y: 24, width: 10, height: 20)))
            manager.selectionMembership = .cutting
            let before = try selectionInk(f.vector)
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 18, y: 32)), [0, 0, 255, 255])
            manager.history.removeAll()

            XCTAssertTrue(manager.beginVectorLassoMove())
            let part = try XCTUnwrap(manager.vectorFloat?.parts.first)
            XCTAssertEqual(part.displayed?.frame, 2)
            XCTAssertFalse(part.insideIDs.contains(originalID), "Cut made fresh piece IDs")
            XCTAssertEqual(part.poses.count, part.insideIDs.count, "fresh pieces retain the source cel and document parent")
            XCTAssertEqual(part.poses.values.first?.affine?.tx ?? .nan, -32, accuracy: 1e-7)
            XCTAssertEqual(part.poses.values.first?.affine?.ty ?? .nan, 8, accuracy: 1e-7)
            XCTAssertEqual(manager.vectorFloat?.pivot.x ?? .nan, 17.5, accuracy: 1e-7, "fresh Cut box surrounds shown right half")
            XCTAssertEqual(manager.vectorFloat?.pivot.y ?? .nan, 32, accuracy: 1e-7)
            var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
            moved.position.x += 8
            manager.nudgeVectorFloat(to: moved)
            XCTAssertTrue(manager.commitVectorFloatIfNeeded())
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 12, y: 32)), [0, 0, 255, 255], "outside half stays")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 18, y: 32))[3], 0, "inside half leaves its shown place")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 24, y: 32)), [0, 0, 255, 255], "piece follows the eight-point drag")
            XCTAssertEqual(manager.history.undoStack.count, sourceOnly ? 1 : 2,
                           "one drag, plus the existing seed write when both source keys are present")
            manager.undo()
            if !sourceOnly { manager.undo() }
            XCTAssertEqual(try selectionInk(f.vector), before)
        }
    }

    @MainActor
    func testRepeatedDuplicateBakesSourceChannelsAndKeepsSourceInkThroughItsTwoUndoSteps() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            select(manager, 0, loop(CGRect(x: 6, y: 33, width: 22, height: 6)))
            let original = try selectionInk(f.vector)
            let sourceID = manager.layers[0].cels[0].id
            let sourcePixel = try memoPixel(manager, at: CGPoint(x: 15, y: 36))
            XCTAssertGreaterThan(sourcePixel[2], 100)
            manager.history.removeAll()

            XCTAssertTrue(manager.beginVectorLassoDuplicate())
            XCTAssertEqual(manager.layers.count, 4)
            let copied = try XCTUnwrap(manager.vectorFloat?.parts.first)
            XCTAssertNotEqual(copied.celID, sourceID)
            XCTAssertEqual(copied.displayed?.frame, 2)
            XCTAssertEqual(copied.displayed?.inheritedPose?.affine?.ty ?? .nan, 8, accuracy: 1e-7)
            XCTAssertEqual(manager.vectorFloat?.pivot.x ?? .nan, 15, accuracy: 1e-7)
            XCTAssertEqual(manager.vectorFloat?.pivot.y ?? .nan, 36, accuracy: 1e-7, "copy's box includes the document parent once")
            XCTAssertEqual(manager.layers[1].cels[0].startFrame, 0)
            XCTAssertEqual(manager.layers[1].cels[0].frameCount, sourceOnly ? 3 : 24)
            XCTAssertEqual(try selectionInk(f.vector), original)
            var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
            moved.position.x += 12
            manager.nudgeVectorFloat(to: moved)
            XCTAssertTrue(manager.commitVectorFloatIfNeeded())
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36)), sourcePixel, "source is unchanged")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 27, y: 36)), sourcePixel, "copy has source-time group pose and parent once")
            XCTAssertEqual(manager.history.undoStack.count, 2, "layer insertion and one nudge")
            manager.undo()
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 27, y: 36))[3], 0)
            manager.undo()
            XCTAssertEqual(manager.layers.count, 3)
            XCTAssertEqual(try selectionInk(f.vector), original)
            manager.redo()
            manager.redo()
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 27, y: 36)), sourcePixel)
            XCTAssertEqual(try selectionInk(f.vector), original)
        }
    }

    /// Half-scale cel × double-scale parent and identity × identity have the same latched map.
    /// Only accepted source time and the separate parent can price the old six-point drag correctly.
    @MainActor
    func testRepeatedMoveKeysAcceptedSourceAndParentAcrossDoneNavigationLayerSaveAndIndexChanges() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for terminal in ["done", "navigate", "layer", "save", "index", "pointer"] {
            let f = try repeatedSelectionFixture(sourceOnly: false)
            let manager = f.manager
            let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
            f.vector.elements = []
            f.vector.addFill(path: loop(CGRect(x: 20, y: 20, width: 8, height: 8)), color: colour(0, 0, 1))
            manager.layers[0].cels[0].startFrame = 2
            manager.layers[0].cels[0].frameCount = 22
            let sourceID = manager.layers[0].cels[0].id
            let layerID = manager.layers[0].id
            manager.layers[0].cels[0].transformTracks = [TransformChannelID.cel.id:
                CanvasFixture.poseTrack([
                    (0, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 0.5, y: 0.5))),
                    (1, PoseQuad(restingIn: box))], interpolation: .linear)]
            manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: box),
                track: CanvasFixture.poseTrack([
                    (2, PoseQuad(restingIn: box)),
                    (14, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 2, y: 2))),
                    (15, PoseQuad(restingIn: box))], interpolation: .linear))
            manager.selection = nil
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 23)), [0, 0, 255, 255], "PRE: cancelling scale maps show the original square")
            let before = try selectionInk(f.vector)
            manager.history.removeAll()
            XCTAssertTrue(manager.beginVectorWholeCelMove())
            XCTAssertTrue(try XCTUnwrap(manager.vectorFloat?.parts.first).poses.isEmpty, "the composed map cannot identify the accepted time or parent")
            if terminal == "pointer" {
                manager.moveBoxTouched()
                manager.currentFrame = 15
                XCTAssertTrue(manager.moveBoxIsTouched)
                XCTAssertEqual(manager.vectorFloat?.parts.first?.displayed?.frame, 2,
                               "a held pointer still owes its old source2 drag before any incoming reprepare")
            }
            var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
            moved.position.x += 6
            manager.nudgeVectorFloat(to: moved)
            var loaded: CanvasManager?
            if terminal == "pointer" {
                manager.moveBoxLifted()
                XCTAssertFalse(manager.moveBoxIsTouched)
                XCTAssertNotNil(manager.vectorFloat, "pointer lift leaves the incoming held-cel box ready")
                XCTAssertEqual(manager.vectorFloat?.parts.first?.displayed?.frame, 3)
            } else if terminal == "navigate" {
                manager.currentFrame = 15
                XCTAssertNotNil(manager.vectorFloat, "same held cel keeps a usable box for the incoming frame")
                XCTAssertEqual(manager.vectorFloat?.parts.first?.displayed?.frame, 3)
            } else if terminal == "layer" {
                manager.currentLayerIndex = 1
                XCTAssertNil(manager.vectorFloat, "a different layer keeps its existing terminal contract")
            } else if terminal == "index" {
                XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 0, frameCount: 1))
                XCTAssertEqual(manager.layers[0].cels.firstIndex { $0.id == sourceID }, 1)
                XCTAssertTrue(manager.commitVectorFloatIfNeeded())
            } else if terminal == "save" {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("repeat-move-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let backupRoot = ProjectBackupManager.rootDirectoryOverride
                ProjectBackupManager.rootDirectoryOverride = root
                defer {
                    ProjectBackupManager.rootDirectoryOverride = backupRoot
                    try? FileManager.default.removeItem(at: root)
                }
                let url = root.appendingPathComponent("accepted.paintproj", isDirectory: true)
                let finished = expectation(description: "accepted Move save")
                ProjectStore.save(manager, to: url) { _ in finished.fulfill() }
                wait(for: [finished], timeout: 30)
                loaded = try XCTUnwrap(ProjectStore.load(from: url))
            } else {
                XCTAssertTrue(manager.commitVectorFloatIfNeeded())
            }
            // Navigation may have left a fresh, unmoved box; land it before compositor assertions.
            _ = manager.commitVectorFloatIfNeeded()
            let at = try XCTUnwrap(manager.celIndices(forCel: sourceID, inLayer: layerID))
            let track = try XCTUnwrap(manager.layers[at.layer].cels[at.cel].transformTracks[TransformChannelID.cel.id])
            XCTAssertEqual(track.curve(.x)?.key(atFrame: 0)?.value ?? -1, 19, accuracy: 1e-7,
                           "source2: centre16 plus local3, priced through accepted parent2")
            XCTAssertEqual(track.curve(.x)?.key(atFrame: 1)?.value ?? -1, 32, accuracy: 1e-7, "incoming source3 remains identity")
            XCTAssertNil(track.curve(.x)?.key(atFrame: 12), "no document14 key in a cel beginning at2")
            XCTAssertNil(track.curve(.x)?.key(atFrame: 13), "no late document15 key")
            manager.currentLayerIndex = at.layer
            manager.currentFrame = 14
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 29, y: 23)), [0, 0, 255, 255])
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 23))[3], 0)
            manager.currentFrame = 15
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 23)), [0, 0, 255, 255])
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 29, y: 23))[3], 0)
            if let loaded {
                let saved = try XCTUnwrap(loaded.celIndices(forCel: sourceID, inLayer: layerID))
                XCTAssertEqual(loaded.layers[saved.layer].cels[saved.cel].transformTracks[TransformChannelID.cel.id], track)
                loaded.currentFrame = 14
                XCTAssertEqual(try memoPixel(loaded, at: CGPoint(x: 29, y: 23)), [0, 0, 255, 255])
            }
            XCTAssertEqual(manager.history.undoStack.count, terminal == "index" ? 3 : 2, "existing key-then-drag history, plus the explicit insertion")
            manager.undo()
            if terminal == "index" { manager.undo() }
            manager.undo()
            XCTAssertEqual(try selectionInk(f.vector), before, "Undo reaches exact original source geometry")
            manager.redo()
            if terminal == "index" { manager.redo() }
            manager.redo()
            manager.currentFrame = 14
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 29, y: 23)), [0, 0, 255, 255])
        }
    }

    @MainActor
    func testRepeatedGroupMoveKeysItsSourceChannelThroughTheSourceCelAndDocumentParent() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        let f = try repeatedSelectionFixture(sourceOnly: false)
        let manager = f.manager
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        f.vector.elements = []
        f.vector.addFill(path: loop(CGRect(x: 2, y: 44, width: 8, height: 8)), color: colour(1, 0, 0))
        f.vector.addFill(path: loop(CGRect(x: 20, y: 20, width: 8, height: 8)), color: colour(0, 0, 1))
        let blue = try XCTUnwrap(f.vector.elements.last?.id)
        f.vector.elements = f.vector.elements.map { $0.id == blue ? $0.taggedForAnimation(f.blueGroup) : $0 }
        f.vector.bumpVersion()
        manager.layers[0].cels[0].startFrame = 2
        manager.layers[0].cels[0].frameCount = 22
        manager.layers[0].cels[0].transformTracks = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack([
                (0, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 0.5, y: 0.5))),
                (1, PoseQuad(restingIn: box))], interpolation: .linear),
            TransformChannelID.group(f.blueGroup).id: TransformTrack(box: box, curves: [
                .x: AnimationCurve(keys: [.init(frame: 0, value: 36), .init(frame: 1, value: 40)])])]
        manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: box),
            track: CanvasFixture.poseTrack([
                (2, PoseQuad(restingIn: box)),
                (14, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 2, y: 2))),
                (15, PoseQuad(restingIn: box))], interpolation: .linear))
        manager.selection = nil
        manager.tapComposition = .add
        manager.selectObject(at: CGPoint(x: 27, y: 23))
        XCTAssertEqual(manager.selection?.objects?.elements, Set([blue]))
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 27, y: 23)), [0, 0, 255, 255], "PRE: group4, celhalf and parent2 compose to a four-point slide")
        let original = try selectionInk(f.vector)
        manager.history.removeAll()
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(manager.vectorFloat?.parts.first?.insideIDs, Set([blue]))
        var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        moved.position.x += 6
        manager.nudgeVectorFloat(to: moved)
        manager.commitVectorFloatIfNeeded()
        let tracks = manager.layers[0].cels[0].transformTracks
        let group = try XCTUnwrap(tracks[TransformChannelID.group(f.blueGroup).id])
        XCTAssertEqual(group.curve(.x)?.key(atFrame: 0)?.value ?? -1, 42, accuracy: 1e-7,
                       "group translation4 plus screen6 through sourcecelhalf and docparent2")
        XCTAssertEqual(group.curve(.x)?.key(atFrame: 1)?.value ?? -1, 40, accuracy: 1e-7, "other source frame stays")
        XCTAssertEqual(tracks[TransformChannelID.cel.id]?.curve(.x)?.key(atFrame: 0)?.value ?? -1, 16, accuracy: 1e-7,
                       "the group edit leaves the source cel channel alone")
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 25, y: 23))[3], 0)
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 35, y: 23)), [0, 0, 255, 255])
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 6, y: 47)), [255, 0, 0, 255], "unselected red is unchanged")
        XCTAssertEqual(manager.history.undoStack.count, 2)
        manager.undo()
        manager.undo()
        XCTAssertEqual(try selectionInk(f.vector), original)
        XCTAssertEqual(manager.layers[0].cels[0].transformTracks[TransformChannelID.group(f.blueGroup).id]?
            .curve(.x)?.key(atFrame: 0)?.value ?? -1, 36, accuracy: 1e-7)
        manager.redo()
        manager.redo()
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 35, y: 23)), [0, 0, 255, 255])
        manager.currentFrame = 15
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 31, y: 23)), [0, 0, 255, 255])
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 37, y: 23))[3], 0, "source3 keeps its eight-point slide")
    }

    @MainActor
    func testHeldCelKeyAThenScrubThenKeyBLeavesTheSelectedMoveBoxReadyForTheNextDrag() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for tapped in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: false)
            let manager = f.manager
            f.vector.elements = []
            f.vector.addFill(path: loop(CGRect(x: 20, y: 20, width: 8, height: 8)), color: colour(0, 0, 1))
            manager.layers[0].cels[0].transformTracks = [:]
            manager.layers[1].transform = nil
            manager.layers[2].transform = nil
            manager.currentFrame = 0
            manager.selection = nil
            if tapped {
                manager.tapComposition = .add
                manager.selectObject(at: CGPoint(x: 24, y: 24))
            }
            let ids = Set(f.vector.elements.map(\.id))
            let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 0))
            XCTAssertTrue(manager.addKeys(target, atFrame: 0))
            XCTAssertTrue(tapped ? manager.beginVectorLassoMove() : manager.beginVectorWholeCelMove())
            manager.turnVectorFloatBox(to: 0.25)
            manager.currentFrame = 8
            let continued = try XCTUnwrap(manager.vectorFloat, "scrubbing a held cel must not require another Move press")
            XCTAssertEqual(continued.parts[0].insideIDs, ids)
            XCTAssertEqual(continued.parts[0].displayed?.frame, 8)
            XCTAssertEqual(continued.frame.boxAngle, 0.25, accuracy: 1e-9)
            if tapped { XCTAssertEqual(manager.selection?.objects?.elements, ids, "selected objects survive") }
            XCTAssertTrue(manager.addKeys(target, atFrame: 8))
            manager.history.removeAll()
            var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
            moved.position.x += 6
            manager.nudgeVectorFloat(to: moved)
            XCTAssertTrue(manager.commitVectorFloatIfNeeded())
            let track = try XCTUnwrap(manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id])
            XCTAssertEqual(track.curve(.x)?.key(atFrame: 0)?.value ?? -1, 24, accuracy: 1e-7)
            XCTAssertEqual(track.curve(.x)?.key(atFrame: 8)?.value ?? -1, 30, accuracy: 1e-7)
            XCTAssertEqual(manager.history.undoStack.count, 2, "seed/key and drag retain their existing steps")
            manager.currentFrame = 0
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 23)), [0, 0, 255, 255], "A stays")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 31, y: 23))[3], 0)
            manager.currentFrame = 8
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 23))[3], 0)
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 31, y: 23)), [0, 0, 255, 255], "B receives the drag")
        }
    }

    @MainActor
    func testAuthoredMoveBeforeHeldCelScrubKeepsItsPendingBaselineAndNextDragKeysOnlyTheNewFrame() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        let f = try repeatedSelectionFixture(sourceOnly: false)
        let manager = f.manager
        f.vector.elements = []
        f.vector.addFill(path: loop(CGRect(x: 20, y: 20, width: 8, height: 8)), color: colour(0, 0, 1))
        manager.layers[0].cels[0].transformTracks = [:]
        manager.layers[1].transform = nil
        manager.layers[2].transform = nil
        manager.selection = nil
        manager.currentFrame = 0
        manager.tapComposition = .add
        manager.selectObject(at: CGPoint(x: 24, y: 24))
        let selected = Set(f.vector.elements.map(\.id))
        let target = try XCTUnwrap(manager.keyframeTarget(layerIndex: 0))
        manager.addKeys(target, atFrame: 0)
        XCTAssertTrue(manager.beginVectorLassoMove())
        var first = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        first.position.x += 4
        manager.nudgeVectorFloat(to: first)
        manager.currentFrame = 8
        XCTAssertNotNil(manager.vectorFloat, "the next drag keeps its box")
        XCTAssertEqual(manager.selection?.objects?.elements, selected, "authored old movement keeps the selected objects for the new drag")
        XCTAssertEqual(manager.layers[0].cels[0].pendingPoseBaselines.count, 1, "old drag holds its existing baseline until B")
        XCTAssertTrue(manager.layers[0].cels[0].transformTracks.isEmpty)
        XCTAssertTrue(manager.addKeys(target, atFrame: 8))
        let seeded = try XCTUnwrap(manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id])
        XCTAssertEqual(seeded.curve(.x)?.key(atFrame: 0)?.value ?? -1, 24, accuracy: 1e-7)
        XCTAssertEqual(seeded.curve(.x)?.key(atFrame: 8)?.value ?? -1, 28, accuracy: 1e-7)
        XCTAssertTrue(manager.layers[0].cels[0].pendingPoseBaselines.isEmpty)
        let history = manager.history.undoStack.count
        var second = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        second.position.x += 6
        manager.nudgeVectorFloat(to: second)
        manager.commitVectorFloatIfNeeded()
        let keyed = try XCTUnwrap(manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id])
        XCTAssertEqual(keyed.curve(.x)?.key(atFrame: 0)?.value ?? -1, 24, accuracy: 1e-7)
        XCTAssertEqual(keyed.curve(.x)?.key(atFrame: 8)?.value ?? -1, 34, accuracy: 1e-7)
        XCTAssertEqual(manager.history.undoStack.count - history, 2, "existing .key restoration then nudge Undo")
        manager.currentFrame = 0
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 23)), [0, 0, 255, 255])
        manager.currentFrame = 8
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 35, y: 23)), [0, 0, 255, 255])
        manager.undo()
        manager.undo()
        XCTAssertEqual(manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id], seeded)
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 29, y: 23)), [0, 0, 255, 255], "undoing second drag retains first")
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 35, y: 23))[3], 0)
    }

    @MainActor
    func testAnUnnudgedCutSurvivesAHeldCelScrubAndFirstUndoStillRejoinsTheOriginalInk() throws {
        let f = try repeatedSelectionFixture(sourceOnly: false)
        let manager = f.manager
        f.vector.elements = []
        f.vector.addFill(path: loop(CGRect(x: 20, y: 20, width: 8, height: 8)), color: colour(0, 0, 1))
        manager.layers[0].cels[0].transformTracks = [:]
        manager.layers[1].transform = nil
        manager.layers[2].transform = nil
        manager.currentFrame = 0
        select(manager, 0, loop(CGRect(x: 24, y: 18, width: 8, height: 12)))
        manager.selectionMembership = .cutting
        let original = try selectionInk(f.vector)
        let originalID = try XCTUnwrap(f.vector.elements.first?.id)
        manager.history.removeAll()
        XCTAssertTrue(manager.beginVectorLassoMove())
        let cutIDs = try XCTUnwrap(manager.vectorFloat?.parts.first?.insideIDs)
        XCTAssertFalse(cutIDs.contains(originalID))
        var landings = 0
        manager.onLivePictureWillLand = { landing in
            guard case .vectorFloat(let old) = landing else { return XCTFail("a vector context replacement lands its vector picture") }
            landings += 1
            XCTAssertEqual(old.parts[0].displayed?.frame, 0)
            XCTAssertEqual(old.parts[0].insideIDs, cutIDs)
            XCTAssertEqual(manager.vectorFloat?.parts.first?.displayed?.frame, 0,
                           "the old context is live until its exact shown picture has been retained")
            XCTAssertEqual(old.nudges, 0)
            XCTAssertTrue(manager.history.undoStack.isEmpty, "replacing an unmoved context authors no history")
        }
        defer { manager.onLivePictureWillLand = nil }
        manager.currentFrame = 8
        XCTAssertEqual(landings, 1, "one admitted replacement releases one old picture latch")
        manager.onLivePictureWillLand = nil
        XCTAssertEqual(manager.vectorFloat?.parts.first?.insideIDs, cutIDs)
        XCTAssertEqual(manager.vectorFloat?.parts.first?.displayed?.frame, 8)
        XCTAssertNotNil(manager.selection)
        XCTAssertTrue(manager.history.undoStack.isEmpty, "a scrub authors no movement or history")
        var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        moved.position.x += 6
        manager.nudgeVectorFloat(to: moved)
        manager.commitVectorFloatIfNeeded()
        XCTAssertEqual(manager.history.undoStack.count, 1)
        manager.undo()
        XCTAssertEqual(try selectionInk(f.vector), original, "first Undo restores the whole original, not a pre-split approximation")
        XCTAssertNil(manager.vectorFloat)
    }

    func testRepeatedMoveAndDuplicateRefuseTheShownDerivedCelAndKeepStandaloneAdmissionAtomic() throws {
        for duplicate in [false, true] {
            for shownLinked in [false, true] {
                let f = try repeatedSelectionFixture(sourceOnly: true)
                let manager = f.manager
                manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1)
                manager.layers[0].cels[shownLinked ? 0 : 1].interpolation = InterpolationRecipe(mode: .reproject)
                let before = try selectionInk(f.vector)
                let layers = manager.layers.map(\.id)
                manager.history.removeAll()
                let accepted = duplicate ? manager.beginVectorLassoDuplicate() : manager.beginVectorLassoMove()
                XCTAssertEqual(accepted, !shownLinked)
                if shownLinked {
                    XCTAssertNil(manager.vectorFloat)
                    XCTAssertEqual(manager.notice?.kind, .cannotMoveDerivedFrame)
                    XCTAssertEqual(manager.layers.map(\.id), layers)
                    XCTAssertEqual(try selectionInk(f.vector), before)
                    XCTAssertTrue(manager.history.undoStack.isEmpty)
                } else {
                    XCTAssertNotNil(manager.vectorFloat)
                    if duplicate { XCTAssertEqual(try selectionInk(f.vector), before) }
                    manager.cancelVectorFloat()
                }
            }
        }
        let f = try repeatedSelectionFixture(sourceOnly: true)
        let manager = f.manager
        let before = try selectionInk(f.vector)
        XCTAssertTrue(manager.beginStructureGesture())
        XCTAssertFalse(manager.beginVectorLassoDuplicate(), "a standalone transfer refuses the enclosing gesture before settlement")
        XCTAssertEqual(try selectionInk(f.vector), before)
        XCTAssertEqual(manager.layers.count, 3)
        XCTAssertNotNil(manager.selection)
        manager.cancelStructureGesture()
    }

    @MainActor
    func testRepeatedSelectionsReadAndRecolourTheShownSourceCelThroughHistory() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager, vector = f.vector
            let original = try selectionInk(vector)
            let sourceID = manager.layers[0].cels[0].id
            XCTAssertEqual(manager.displayedFrame(forLayer: 0, atFrame: 14), 2)
            XCTAssertEqual(manager.activeCelIndex(inLayer: 0, atFrame: 14) == nil, sourceOnly)
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[2], 100)
            XCTAssertNil(manager.selectionEditUnavailableReason)
            XCTAssertNil(manager.animationGroupEditUnavailableReason)
            for _ in 0..<3 {
                XCTAssertEqual(manager.selectionStyle.color, colour(0, 0, 1), "the fixed loop reads the shown source's blue")
                XCTAssertEqual(manager.selectionStyle.size, 8)
                XCTAssertEqual(manager.selectionStyle.opacity, 0.5)
                XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group", "the fixed loop names the shown source group")
            }
            XCTAssertTrue(manager.beginSelectionEdit(.color))
            manager.previewSelectionEdit(.color(colour(0, 0, 1)))
            XCTAssertFalse(manager.commitSelectionEdit(), "an untouched source readout records nothing")
            XCTAssertTrue(try selectionInk(vector) == original)
            XCTAssertEqual(manager.history.undoStack.count, 0)
            XCTAssertTrue(manager.applySelectionEdit(.color(colour(0, 1, 0))))
            XCTAssertEqual(manager.layers[0].cels.map(\.id), [sourceID], "no cel is created at the playhead")
            XCTAssertEqual(vector.elements.first { $0.id == f.red }?.stroke?.color, colour(1, 0, 0))
            XCTAssertEqual(vector.elements.first { $0.id == f.blue }?.stroke?.color, colour(0, 1, 0))
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[1], 100)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            XCTAssertTrue(try selectionInk(vector) == original, "Undo restores all source geometry and style")
            XCTAssertEqual(manager.selectionStyle.color, colour(0, 0, 1))
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[2], 100)
            manager.redo()
            XCTAssertEqual(manager.selectionStyle.color, colour(0, 1, 0))
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[1], 100)
            if !sourceOnly {
                manager.undo()
                XCTAssertEqual(manager.selectionStyle.color, colour(0, 0, 1), "warm both source-time keys")
                XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group")
                let version = vector.version
                // Only the source key changes; the exact key at document14 stays at32. A memo
                // keyed at document time would remain warm while the actual shown mark changes.
                manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id] = TransformTrack(
                    box: CGRect(origin: .zero, size: CanvasFixture.canvasSize),
                    curves: [.x: AnimationCurve(keys: [.init(frame: 2, value: 32), .init(frame: 14, value: 32)])])
                XCTAssertEqual(manager.currentFrame, 14)
                XCTAssertEqual(vector.version, version)
                XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 28))[0], 200)
                XCTAssertEqual(manager.selectionStyle.color, colour(1, 0, 0), "a source-key edit invalidates the style memo")
                XCTAssertEqual(manager.selectionAnimationGroupName, "Red group", "a source-key edit invalidates the group memo")
            }
        }
    }

    @MainActor
    func testRepeatedSelectionGroupCompensationUsesSourceTimeAndKeepsThePictureThroughHistory() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager, vector = f.vector
            let original = try selectionInk(vector)
            let before = try memoPixel(manager, at: CGPoint(x: 15, y: 36))
            XCTAssertGreaterThan(before[2], 100)
            XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group", "the group readout starts on the shown source")
            XCTAssertTrue(manager.setAnimationGroupOfSelection(.existing(f.redGroup)))
            XCTAssertEqual(vector.elements.first { $0.id == f.blue }?.animationGroupID, f.redGroup)
            XCTAssertEqual(vector.elements.first { $0.id == f.red }?.animationGroupID, f.redGroup)
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36)), before,
                           "source-time compensation preserves the shown blue mark")
            XCTAssertEqual(manager.selectionAnimationGroupName, "Red group")
            XCTAssertFalse(manager.setAnimationGroupOfSelection(.existing(f.redGroup)), "same group is an exact no-op")
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            XCTAssertTrue(try selectionInk(vector) == original)
            XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group")
            manager.redo()
            XCTAssertEqual(manager.selectionAnimationGroupName, "Red group")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36)), before)
        }
    }

    @MainActor
    func testRepeatedTapAndSelectEditOpenTheShownSourceTextAndKeepItsNoOpExact() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager, vector = f.vector
            var redRecipe = TextRecipe(string: "A"), blueRecipe = TextRecipe(string: "B")
            redRecipe.color = colour(1, 0, 0)
            blueRecipe.color = colour(0, 0, 1)
            redRecipe.typography = Typography(pointSize: 12)
            blueRecipe.typography = Typography(pointSize: 12)
            let left = VectorTextElement(recipe: redRecipe,
                frame: TextFrame(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 16, height: 18), autoSize: false),
                animationGroupID: f.redGroup)
            let right = VectorTextElement(recipe: blueRecipe,
                frame: TextFrame(origin: CGPoint(x: 42, y: 20), size: CGSize(width: 16, height: 18), autoSize: false),
                animationGroupID: f.blueGroup)
            vector.elements = [.text(left), .text(right)]
            let original = try selectionInk(vector)
            let beforePixels = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            XCTAssertTrue(stride(from: 3, to: beforePixels.count, by: 4).contains { beforePixels[$0] > 0 },
                          "the repeated source text actually draws")
            let sourceID = manager.layers[0].cels[0].id
            XCTAssertEqual(manager.selectionStyle.editableObjects[.text], right.id, "Select offers the displayed source label")
            XCTAssertTrue(manager.editSelectedObject(.text))
            XCTAssertEqual(manager.textEditingElementID, right.id)
            XCTAssertEqual(manager.textGestureCelID, sourceID)
            XCTAssertEqual(manager.textRecipe.string, "B")
            XCTAssertEqual(manager.textFrame.corners, right.frame.corners.map { CGPoint(x: $0.x - 32, y: $0.y + 16) })
            manager.commitInteractiveText()
            XCTAssertTrue(try selectionInk(vector) == original)
            XCTAssertTrue(try CanvasFixture.rgbaBytes(memoPicture(manager)) == beforePixels)
            XCTAssertEqual(manager.history.undoStack.count, 0)
            manager.tapComposition = .add
            _ = manager.selectObject(at: CGPoint(x: 15, y: 40))
            XCTAssertEqual(manager.selection?.objects?.celID, sourceID, "Tap selects the displayed source cel")
            XCTAssertEqual(manager.selection?.objects?.elements, Set([right.id]), "Tap names the shown blue label")
            manager.currentFrame = 2
            manager.currentFrame = 14
            XCTAssertEqual(manager.selection?.objects?.elements, Set([right.id]),
                           "the same source cel keeps its tapped selection across Repeat ticks")
            manager.undo()
            XCTAssertNil(manager.selection?.objects)
            manager.redo()
            XCTAssertEqual(manager.selection?.objects?.elements, Set([right.id]), "Redo restores a tapped source selection")
            manager.tapComposition = .subtract
            _ = manager.selectObject(at: CGPoint(x: 15, y: 40))
            XCTAssertNil(manager.selection, "Subtract hits the shown source object")
            manager.undo()
            XCTAssertEqual(manager.selection?.objects?.elements, Set([right.id]), "Undo restores the subtracted source object")
            XCTAssertEqual(manager.selectionStyle.editableObjects[.text], right.id)
            XCTAssertTrue(manager.editSelectedObject(.text))
            manager.textRecipe.string = "C"
            manager.textRecipeDidChange()
            manager.commitInteractiveText()
            XCTAssertEqual(vector.elements.compactMap(\.text).map(\.id), [left.id, right.id])
            XCTAssertEqual(vector.elements.compactMap(\.text).first { $0.id == left.id }, left)
            XCTAssertEqual(vector.elements.compactMap(\.text).first { $0.id == right.id }?.recipe.string, "C")
            XCTAssertEqual(manager.history.undoStack.count, 2, "one tap selection and one text edit")
            let editedPixels = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            XCTAssertFalse(editedPixels == beforePixels, "typing changes the actual repeated source letters")
            manager.undo()
            XCTAssertTrue(try selectionInk(vector) == original)
            XCTAssertTrue(try CanvasFixture.rgbaBytes(memoPicture(manager)) == beforePixels)
            manager.redo()
            XCTAssertEqual(vector.elements.compactMap(\.text).first { $0.id == right.id }?.recipe.string, "C")
            XCTAssertTrue(try CanvasFixture.rgbaBytes(memoPicture(manager)) == editedPixels)
        }
    }

    @MainActor
    func testRepeatedGradientEditUsesTheShownSourceAndItsLiveWindowThroughHistory() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager, vector = f.vector
            // The untagged fill follows only cel + parent; removing the strokes makes every
            // remaining element share the one pose required by the editor's existing live window.
            vector.elements = []
            let rect = CGRect(x: 42, y: 20, width: 12, height: 8)
            let id = vector.addFill(path: loop(rect),
                paint: .linearGradient(.spanning(rect, angle: 0))).id
            let original = try selectionInk(vector)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            let sourceID = manager.layers[0].cels[0].id
            XCTAssertEqual(manager.selectionStyle.editableObjects[.gradient], id, "Select offers the gradient on the shown source")
            XCTAssertTrue(manager.editSelectedObject(.gradient), "Edit opens the shown source gradient")
            XCTAssertEqual(manager.gradientEdit?.edit.celID, sourceID)
            XCTAssertEqual(manager.gradientEdit?.elementID, id)
            XCTAssertEqual(manager.liveCelContentEdit?.celID, sourceID,
                           "the source-time single-pose check admits a live edit window")
            guard manager.liveCelContentEdit != nil else { continue }
            XCTAssertFalse(manager.commitGradientEdit(), "opening and closing records nothing")
            XCTAssertTrue(try selectionInk(vector) == original)
            XCTAssertEqual(manager.history.undoStack.count, 0)
            XCTAssertTrue(manager.editSelectedObject(.gradient))
            manager.setGradientColour(.start, to: .green)
            let held = try XCTUnwrap(manager.liveCelContentEdit)
            let placement = manager.celContentPlacement(forLayerID: manager.layers[0].id)
            let preview = try XCTUnwrap(held.presentation(placement: placement))
            let sample = CGPoint(x: 15, y: 32)
            let coversSample = preview.window.contains(sample)
            XCTAssertTrue(coversSample, "the live window covers the shown source gradient")
            guard coversSample else { continue }
            let cg = try XCTUnwrap(preview.image.cgImage)
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
            let x = Int((sample.x - preview.window.minX) * CGFloat(cg.width) / preview.window.width)
            let y = Int((sample.y - preview.window.minY) * CGFloat(cg.height) / preview.window.height)
            let offset = (y * cg.width + x) * 4
            XCTAssertGreaterThan(pixels[offset + 1], pixels[offset],
                                 "the rewritten green gradient is drawn inside its shown live window")
            XCTAssertTrue(manager.commitGradientEdit())
            let edited = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            XCTAssertFalse(edited == before, "the gradient's new colour is drawn on the repeated source")
            XCTAssertEqual(vector.elements.map(\.id), [id])
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            XCTAssertTrue(try selectionInk(vector) == original)
            XCTAssertTrue(try CanvasFixture.rgbaBytes(memoPicture(manager)) == before)
            manager.redo()
            XCTAssertTrue(try CanvasFixture.rgbaBytes(memoPicture(manager)) == edited)
        }
    }

    func testRepeatedSelectionAdmissionUsesTheShownCelsLinkedStatus() throws {
        for shownLinked in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: true)
            let manager = f.manager
            manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1)
            manager.layers[0].cels[shownLinked ? 0 : 1].interpolation = InterpolationRecipe(mode: .reproject)
            let before = try selectionInk(f.vector)
            let history = manager.history.undoStack.count
            if shownLinked {
                XCTAssertTrue(manager.selectionEditUnavailableReason?.contains("in-between") == true,
                              "the shown linked cel refuses the selection band")
                XCTAssertTrue(manager.animationGroupEditUnavailableReason?.contains("in-between") == true,
                              "the shown linked cel refuses group assignment")
                XCTAssertEqual(manager.selectionStyle, .unavailable)
                XCTAssertEqual(manager.selectionAnimationGroup, .unavailable)
                XCTAssertFalse(manager.applySelectionEdit(.color(colour(0, 1, 0))))
                XCTAssertFalse(manager.setAnimationGroupOfSelection(.none))
                XCTAssertTrue(try selectionInk(f.vector) == before)
                XCTAssertEqual(manager.history.undoStack.count, history)
            } else {
                XCTAssertNil(manager.selectionEditUnavailableReason, "an ordinary shown cel keeps its selection band")
                XCTAssertNil(manager.animationGroupEditUnavailableReason, "an ordinary shown cel keeps group assignment")
                XCTAssertEqual(manager.selectionStyle.color, colour(0, 0, 1))
                XCTAssertEqual(manager.selectionAnimationGroupName, "Blue group")
            }
        }
    }

    @MainActor
    func testRepeatedClearDeletesOnlyTheShownSourceMarksThroughHistory() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            let tightLoop = CGRect(x: 6, y: 33, width: 22, height: 6)
            manager.selection = Selection(path: loop(tightLoop), bounds: tightLoop)
            let original = try selectionInk(f.vector)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[2], 100)
            manager.clearSelectionPixels()
            XCTAssertEqual(f.vector.elements.map(\.id), [f.red], "Clear removes the shown source blue, not the raw-time red")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[3], 0, "the loop is visibly clear")
            XCTAssertEqual(manager.currentFrame, 14)
            XCTAssertEqual(manager.layers[0].cels.count, 1)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            XCTAssertEqual(try selectionInk(f.vector), original)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            manager.redo()
            XCTAssertEqual(f.vector.elements.map(\.id), [f.red])
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[3], 0)
        }
    }

    @MainActor
    func testRepeatedFillLandsOnTheShownSourceInsideTheCanvasLoopThroughHistory() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            let original = try selectionInk(f.vector)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            manager.brushColor = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
            manager.toolProfiles.brush.opacity = 1
            manager.fillSelection()
            XCTAssertEqual(f.vector.elements.count, 3, "Fill appends to the displayed source cel")
            XCTAssertEqual(Array(f.vector.elements.prefix(2).map(\.id)), [f.red, f.blue])
            let fill = try XCTUnwrap(f.vector.elements.last?.fill?.cgPath)
            XCTAssertEqual(fill.boundingBoxOfPath, CGRect(x: 38, y: 18, width: 22, height: 20),
                           "the canvas loop is pulled back through source cel and document parent once")
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[1], 200, "the repeated canvas loop is green")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 35, y: 36))[3], 0, "Fill leaves the loop exterior clear")
            XCTAssertEqual(manager.currentFrame, 14)
            XCTAssertEqual(manager.layers[0].cels.count, 1)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            manager.undo()
            XCTAssertEqual(try selectionInk(f.vector), original)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            manager.redo()
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after)
        }
    }

    @MainActor
    func testRepeatedApplyBrushUsesShownSourceGroupTimingAndUndoesOneVisibleEdit() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            let tightLoop = CGRect(x: 6, y: 33, width: 22, height: 6)
            manager.selection = Selection(path: loop(tightLoop), bounds: tightLoop)
            let original = try selectionInk(f.vector)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            let picked = Brush(id: UUID(), name: "Soft sparse", tip: .round, size: 8,
                               dab: BrushDabSettings(spacing: 0.7, hardness: 0.05))
            manager.selectPreset(picked, for: .brush)
            XCTAssertNil(manager.applyBrushUnavailableReason, "the shown source permits Apply Brush")
            manager.applyBrushToSelection()
            XCTAssertEqual(f.vector.elements.first { $0.id == f.red }?.stroke?.brush, TestBrushes.hardRound)
            XCTAssertEqual(f.vector.elements.first { $0.id == f.blue }?.stroke?.brush, picked,
                           "Apply Brush rewrites the mark shown inside the loop")
            let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            XCTAssertNotEqual(after, before, "the new brush visibly changes the repeated source")
            XCTAssertEqual(manager.currentFrame, 14)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.applyBrushToSelection()
            XCTAssertEqual(manager.history.undoStack.count, 1, "applying the same brush is a no-op")
            manager.undo()
            XCTAssertEqual(try selectionInk(f.vector), original)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            manager.redo()
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after)
        }
    }

    @MainActor
    func testRepeatedToNewLayerPreparesSourceCelAndGroupPoseAndPreservesThePicture() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            let tightLoop = CGRect(x: 6, y: 33, width: 22, height: 6)
            manager.selection = Selection(path: loop(tightLoop), bounds: tightLoop)
            let original = try selectionInk(f.vector)
            let source = manager.layers[0].cels[0]
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            manager.moveSelectionToNewLayer()
            XCTAssertEqual(manager.layers.count, 4, "To New Layer transfers from the shown source")
            guard manager.layers.count == 4 else { continue }
            XCTAssertTrue(manager.commitAllInteractiveState())
            XCTAssertEqual(f.vector.elements.map(\.id), [f.red], "only the shown blue mark leaves the source")
            XCTAssertEqual(manager.layers[1].cels[0].vector?.elements.map(\.id), [f.blue])
            XCTAssertEqual(manager.layers[1].cels[0].startFrame, source.startFrame)
            XCTAssertEqual(manager.layers[1].cels[0].frameCount, source.frameCount)
            XCTAssertTrue(manager.layers[1].cels[0].transformTracks.isEmpty)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before,
                           "source-time cel/group pose is consumed once and document-time parent stays once")
            XCTAssertEqual(manager.currentFrame, 14)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            XCTAssertEqual(manager.layers.count, 3)
            XCTAssertEqual(try selectionInk(f.vector), original)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            manager.redo()
            XCTAssertEqual(manager.layers.count, 4)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
        }
    }

    func testRepeatedApplyBrushAndToNewLayerAdmitOrRefuseTheShownLinkedCel() throws {
        for shownLinked in [false, true] {
            for transfer in [false, true] {
                let f = try repeatedSelectionFixture(sourceOnly: true)
                let manager = f.manager
                manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1)
                manager.layers[0].cels[shownLinked ? 0 : 1].interpolation = InterpolationRecipe(mode: .reproject)
                let original = try selectionInk(f.vector)
                let raw = try selectionInk(XCTUnwrap(manager.layers[0].cels[1].vector))
                manager.history.removeAll()
                manager.selectPreset(Brush(id: UUID(), name: "Other", tip: .round, size: 8,
                    dab: BrushDabSettings(spacing: 0.7, hardness: 0.05)), for: .brush)
                if transfer {
                    XCTAssertEqual(manager.moveVectorSelectionToNewLayer(), !shownLinked,
                                   "To New Layer refuses exactly when the shown cel is linked")
                } else {
                    XCTAssertEqual(manager.applyBrushUnavailableReason?.contains("in-between") == true, shownLinked)
                    manager.applyBrushToSelection()
                }
                XCTAssertEqual(try selectionInk(XCTUnwrap(manager.layers[0].cels[1].vector)), raw,
                               "the raw-time cel is never rewritten")
                XCTAssertEqual(manager.currentFrame, 14)
                if shownLinked {
                    XCTAssertEqual(try selectionInk(f.vector), original)
                    XCTAssertEqual(manager.history.undoStack.count, 0, "refusal records no transfer or brush edit")
                    XCTAssertEqual(manager.layers.count, 3)
                } else {
                    XCTAssertNotEqual(try selectionInk(f.vector), original, "the ordinary shown source is edited")
                    XCTAssertEqual(manager.history.undoStack.count, 1)
                }
            }
        }
    }

    @MainActor
    func testRepeatedRasterMoveLandsOnTheShownSourceThroughItsAcceptedParentAndOneUndo() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            manager.layers[0].kind = .raster
            manager.layers[0].cels[0].vector = nil
            manager.layers[0].cels[0].transformTracks = [:]
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                CanvasFixture.solidImage(.blue, rect: CGRect(x: 10, y: 20, width: 10, height: 8)))
            let sourceID = manager.layers[0].cels[0].id
            if sourceOnly {
                XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1))
                CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 14,
                    CanvasFixture.solidImage(.red, rect: CGRect(x: 40, y: 20, width: 10, height: 8)))
            }
            let sourceIDs = manager.layers[0].cels.map(\.id)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 32)), [0, 0, 255, 255])
            manager.history.removeAll()
            manager.beginMove()
            let piece = try XCTUnwrap(manager.floatingPiece)
            XCTAssertEqual(piece.sourceCelID, sourceID)
            XCTAssertEqual(piece.targetCelID, sourceID)
            XCTAssertEqual(piece.landingPose?.affine?.ty ?? .nan, 8, accuracy: 1e-7,
                           "the parent uses document14, not source2's minus-eight pose")
            var moved = piece.transform
            moved.position.x += 8
            manager.updateFloatingPose(transform: moved, distortQuad: nil)
            XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 32))[3], 0)
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 23, y: 32)), [0, 0, 255, 255])
            XCTAssertEqual(manager.layers[0].cels.map(\.id), sourceIDs, "Move creates no hidden raw-time cel")
            XCTAssertEqual(manager.currentFrame, 14)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            manager.undo()
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            manager.redo()
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after)
        }
    }

    @MainActor
    func testRepeatedRasterFillClearAndToNewLayerUseTheShownSourceAndHistory() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for sourceOnly in [false, true] {
            for action in ["fill", "clear", "transfer"] {
                let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
                let manager = f.manager
                manager.layers[0].kind = .raster
                manager.layers[0].cels[0].vector = nil
                manager.layers[0].cels[0].transformTracks = [:]
                CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                    CanvasFixture.solidImage(.blue, rect: CGRect(x: 10, y: 20, width: 10, height: 8)))
                let source = manager.layers[0].cels[0]
                let original = try XCTUnwrap(PixelOps.rasterize(cel: source, canvasSize: CanvasFixture.canvasSize)?.cgImage)
                let storedBefore = try XCTUnwrap(CanvasFixture.rgbaBytes(original))
                let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 32))[2], 200)
                if action == "fill" {
                    manager.brushColor = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
                    manager.toolProfiles.brush.opacity = 1
                    manager.fillSelection()
                    XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 32))[1], 200)
                } else if action == "clear" {
                    manager.clearSelectionPixels()
                    XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 32))[3], 0)
                } else {
                    manager.moveSelectionToNewLayer()
                    XCTAssertEqual(manager.layers.count, 4, "the source-only raster drawing can transfer")
                    guard manager.layers.count == 4 else { continue }
                    XCTAssertEqual(manager.layers[1].cels[0].startFrame, source.startFrame)
                    XCTAssertEqual(manager.layers[1].cels[0].frameCount, source.frameCount)
                    XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before,
                                   "the inherited document-time parent carries both layers once")
                }
                let changed = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)?.cgImage)
                XCTAssertNotEqual(CanvasFixture.rgbaBytes(changed), storedBefore, "the shown source raster changes")
                XCTAssertEqual(manager.layers[0].cels.map(\.id), [source.id])
                XCTAssertEqual(manager.currentFrame, 14)
                XCTAssertEqual(manager.history.undoStack.count, 1)
                let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                manager.undo()
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
                manager.redo()
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after)
            }
        }
    }

    @MainActor
    func testRepeatedRasterDuplicateUsesShownPixelsButLandsIndependentlyAtThePressedFrame() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for nested in [false, true] {
            for sourceOnly in [false, true] {
                let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
                let manager = f.manager
                manager.layers[0].kind = .raster
                manager.layers[0].cels[0].vector = nil
                var dormant = try XCTUnwrap(manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id])
                dormant.setCurve(AnimationCurve(keys: [.init(frame: 2, value: 12)]), for: .y)
                manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id] = dormant
                // A Move below Repeat is read at source2 and escaped by the root copy;
                // the outer Move above Repeat remains at document14 on both destinations.
                manager.currentLayerIndex = 0
                manager.addTransformLayer(name: "Source-time Move")
                CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 24)])
                let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
                manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: box),
                    track: CanvasFixture.poseTrack([
                        (2, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: 4))),
                        (14, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: 24)))
                    ], interpolation: .linear))
                manager.currentLayerIndex = 0
                // Pure raster backing never displays its dormant cel/group channels.
                if nested {
                    let folder = try XCTUnwrap(manager.addFolder(name: "Repeated source"))
                    manager.layers[0].parentFolderID = folder
                    manager.layers[1].parentFolderID = folder
                    manager.layers[2].parentFolderID = folder
                }
                CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                    CanvasFixture.solidImage(.blue, rect: CGRect(x: 10, y: 20, width: 10, height: 8)))
                if sourceOnly {
                    XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1))
                    CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 14,
                        CanvasFixture.solidImage(.red, rect: CGRect(x: 40, y: 20, width: 10, height: 8)))
                }
                let sourceID = manager.layers[0].id
                let celID = manager.layers[0].cels[0].id
                let sourceIDs = manager.layers[0].cels.map(\.id)
                let duration = manager.layers[0].cels[0].frameCount
                let original = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                let source = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)))
                let layerIDs = manager.layers.map(\.id)
                manager.history.removeAll()
                manager.beginDuplicate()
                XCTAssertNotNil(manager.floatingPiece, "the shown source can be copied even when raw frame14 is different")
                guard let piece = manager.floatingPiece else { return }
                XCTAssertEqual(piece.sourceLayerID, sourceID)
                XCTAssertEqual(piece.sourceCelID, celID)
                XCTAssertEqual(piece.landingPose?.affine?.ty, 8,
                               "the retained destination parent is removed once; the escaped source-time Move stays baked")
                let target = manager.layers[manager.currentLayerIndex]
                XCTAssertNil(target.parentFolderID, "raster Duplicate remains an independent root copy")
                if let folder = manager.layers[0].parentFolderID {
                    XCTAssertEqual(manager.descendantLayerIndices(ofFolder: folder), [0, 1, 2],
                                   "the independent copy never splits its source folder's contiguous span")
                }
                XCTAssertEqual(target.cels.map(\.startFrame), [14], "the copy starts at the pressed document frame")
                XCTAssertEqual(target.cels.map(\.frameCount), [duration], "the source duration is retained")
                let walk = manager.renderTreeAndPoses(atFrame: 14)
                XCTAssertEqual(manager.displayedCel(inLayer: manager.currentLayerIndex, atFrame: 14, in: walk)?.frame, 14,
                               "the independent destination escapes Repeat's source-time scope")
                var moved = piece.transform
                moved.position.x += 8
                manager.updateFloatingPose(transform: moved, distortQuad: nil)
                XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 36)), [0, 0, 255, 255], "source ink remains")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 25, y: 36)), [0, 0, 255, 255], "the copied shown ink survives Done at frame14")
                XCTAssertEqual(manager.layers[0].cels.map(\.id), sourceIDs)
                XCTAssertEqual(try CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), source)
                XCTAssertEqual(manager.history.undoStack.count, 1, "raster copy and its landing remain one insertion Undo")
                let final = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                manager.currentFrame = 2
                XCTAssertNil(manager.activeCelIndex(inLayer: manager.currentLayerIndex, atFrame: 2), "the independent copy does not occupy its source frame")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 25, y: 16))[3], 0)
                manager.currentFrame = 14
                manager.undo()
                XCTAssertEqual(manager.layers.map(\.id), layerIDs)
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), original)
                manager.redo()
                XCTAssertTrue(manager.layers.contains { $0.id == target.id && $0.parentFolderID == nil && $0.cels[0].startFrame == 14 })
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), final)
            }
        }
    }

    /// Finite, byte-defined input: no colour-space conversion is part of these contribution tests.
    private func duplicateContributionPatch(_ rgba: [UInt8], x: Range<Int>, y: Range<Int>) throws -> UIImage {
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        for row in y {
            for column in x {
                let offset = (row * 64 + column) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: rgba)
            }
        }
        let image = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: 64, height: 64))
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    @MainActor
    func testRasterDuplicateBakesTheEscapedValueGradeAndKeepsRetainedGradeAndMoveOnce() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for retainedGrade in [false, true] {
            for outerMove in [false, true] {
                let manager = CanvasFixture.manager(layerCount: 1)
                let size = CanvasFixture.canvasSize
                manager.layers[0].cels[0].frameCount = 3
                manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
                    duplicateContributionPatch([128, 128, 128, 255], x: 10..<20, y: 20..<28), size: size, strokeCount: 1)
                manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 0.5, contrast: 1)), name: "Escaped grade")
                CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 24)])
                manager.addTransformLayer(name: "Repeat graded source")
                CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 24)])
                let box = CGRect(origin: .zero, size: size)
                manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 12)
                if outerMove {
                    manager.addTransformLayer(name: "Retained Move")
                    manager.layers[manager.currentLayerIndex].transform = LayerPose(
                        pose: PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: 8)))
                }
                if retainedGrade {
                    manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 0.5, contrast: 1)), name: "Retained grade")
                }
                manager.currentLayerIndex = 0
                manager.currentFrame = 14
                let dy: CGFloat = outerMove ? 8 : 0
                let bounds = CGRect(x: 6, y: 16 + dy, width: 20, height: 16)
                manager.selection = Selection(path: loop(bounds), bounds: bounds)
                manager.history.removeAll()
                let originalIDs = manager.layers.map(\.id)
                let sourceIDs = manager.layers[0].cels.map(\.id)
                let original = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                let source = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)))
                let expected: [UInt8] = retainedGrade ? [32, 32, 32, 255] : [64, 64, 64, 255]
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 24 + dy)), expected,
                               "PREMISE: the source really shows the escaped grade and optional retained grade")
                XCTAssertNil(manager.activeCelIndex(inLayer: 0, atFrame: 14), "PREMISE: the shown source is reached only through Repeat")
                manager.beginDuplicate()
                XCTAssertNotNil(manager.floatingPiece, "the graded shown source is admitted")
                guard let piece = manager.floatingPiece else { return }
                let targetID = manager.layers[manager.currentLayerIndex].id
                var moved = piece.transform
                moved.position.x += 12
                manager.updateFloatingPose(transform: moved, distortQuad: nil)
                XCTAssertTrue(manager.commitFloatingPieceIfNeeded(), "Done lands the admitted contribution")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 25, y: 24 + dy)), expected,
                               "the copy keeps the escaped grade and applies each retained grade/pose only once")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 24 + dy)), expected, "the displayed source is untouched")
                XCTAssertEqual(manager.layers[0].cels.map(\.id), sourceIDs)
                XCTAssertEqual(try CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), source,
                               "the source's ungraded raster bytes are unchanged")
                XCTAssertEqual(manager.layers[manager.currentLayerIndex].cels.map(\.startFrame), [14])
                XCTAssertEqual(manager.layers[manager.currentLayerIndex].cels.map(\.frameCount), [3])
                XCTAssertEqual(manager.currentFrame, 14)
                XCTAssertEqual(manager.history.undoStack.count, 1, "the contribution and its landing remain one insertion Undo")
                let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                manager.undo()
                XCTAssertEqual(manager.layers.map(\.id), originalIDs, "one Undo removes only the new copy")
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), original, "Undo restores the exact graded source picture")
                manager.redo()
                XCTAssertTrue(manager.layers.contains { $0.id == targetID && $0.parentFolderID == nil && $0.cels[0].startFrame == 14 })
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after, "Redo restores the exact graded copied picture")
            }
        }
    }

    @MainActor
    func testRasterDuplicateBakesEscapedFolderOpacityEffectAndMaskWithoutCopyingItsSibling() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        let manager = CanvasFixture.manager(layerCount: 1)
        let size = CanvasFixture.canvasSize
        manager.layers[0].cels[0].frameCount = 3
        manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
            duplicateContributionPatch([128, 128, 128, 255], x: 10..<20, y: 20..<28), size: size, strokeCount: 1)
        manager.addLayer(name: "Other drawing in the same folder")
        manager.layers[1].cels[0].frameCount = 3
        manager.layers[1].cels[0].raster = try CanvasFixture.rasterTexture(
            duplicateContributionPatch([255, 0, 0, 255], x: 14..<20, y: 12..<16), size: size, strokeCount: 1)
        manager.addTransformLayer(name: "Repeat folder drawings")
        CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 24)])
        let box = CGRect(origin: .zero, size: size)
        manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 12)
        manager.addLayer(name: "Hidden external mask")
        manager.layers[3].cels[0].frameCount = 24
        manager.layers[3].cels[0].raster = try CanvasFixture.rasterTexture(
            duplicateContributionPatch([255, 255, 255, 255], x: 14..<20, y: 10..<32), size: size, strokeCount: 1)
        let maskID = manager.layers[3].id
        manager.layers[3].isVisible = false
        manager.addTransformLayer(name: "Retained outer Move")
        manager.layers[4].transform = LayerPose(pose: PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 0, y: 8)))
        let effectFolder = try XCTUnwrap(manager.addFolder(name: "Escaped effect"))
        for index in 0..<3 { manager.layers[index].parentFolderID = effectFolder }
        let effectIndex = try XCTUnwrap(manager.folders.firstIndex { $0.id == effectFolder })
        manager.folders[effectIndex].effect = .brightnessContrast(.init(brightness: 0.5, contrast: 1))
        let folder = try XCTUnwrap(manager.addFolder(name: "Escaped opacity and mask"))
        let folderIndex = try XCTUnwrap(manager.folders.firstIndex { $0.id == folder })
        manager.folders[effectIndex].parentFolderID = folder
        manager.folders[folderIndex].opacity = 0.5
        let mask = AlphaMask(sources: [.layer(maskID)])
        manager.folders[folderIndex].alphaMask = mask
        manager.currentLayerIndex = 0
        manager.currentFrame = 14
        let bounds = CGRect(x: 6, y: 18, width: 20, height: 22)
        manager.selection = Selection(path: loop(bounds), bounds: bounds)
        manager.history.removeAll()
        let originalIDs = manager.layers.map(\.id)
        let original = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
        let source = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)))
        let expected: [UInt8] = [32, 32, 32, 128]
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 16, y: 32)), expected,
                       "PREMISE: the shown source includes its folder effect and opacity")
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 12, y: 32))[3], 0, "PREMISE: the hidden external source clips the folder")
        XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 16, y: 22))[0], 0,
                             "PREMISE: another painted sibling really lies inside the selected rectangle")
        manager.beginDuplicate()
        XCTAssertNotNil(manager.floatingPiece, "the masked shown source is admitted")
        guard let piece = manager.floatingPiece else { return }
        var moved = piece.transform
        moved.position.x += 12
        manager.updateFloatingPose(transform: moved, distortQuad: nil)
        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 28, y: 32)), expected,
                       "the independent copy keeps the escaped folder effect and opacity")
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 24, y: 32))[3], 0,
                       "the escaped mask moves with the copy instead of revealing previously clipped source pixels")
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 28, y: 22))[3], 0,
                       "the copy contains only the selected source contribution, never its painted sibling")
        XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 16, y: 32)), expected)
        XCTAssertEqual(try CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), source)
        XCTAssertEqual(manager.folders[folderIndex].opacity, 0.5)
        XCTAssertEqual(manager.folders[folderIndex].alphaMask, mask)
        XCTAssertEqual(manager.history.undoStack.count, 1)
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
        manager.undo()
        XCTAssertEqual(manager.layers.map(\.id), originalIDs)
        XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), original, "Undo restores both original folder drawings exactly")
        manager.redo()
        XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after, "Redo restores the exact masked independent copy")
    }

    @MainActor
    func testRasterDuplicateKeepsHiddenSourceAdmissionWithoutTurningOnHiddenGrades() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for hideLayer in [false, true] {
            for gradeVisible in [false, true] {
                let manager = CanvasFixture.manager(layerCount: 1)
                let size = CanvasFixture.canvasSize
                manager.layers[0].cels[0].frameCount = 3
                manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
                    duplicateContributionPatch([128, 128, 128, 255], x: 10..<20, y: 20..<28), size: size, strokeCount: 1)
                let sourceRaster = manager.layers[0].cels[0].raster
                manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 0.5, contrast: 1)), name: "Grade with its own eye")
                CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 24)])
                manager.layers[1].isVisible = gradeVisible
                manager.addTransformLayer(name: "Repeat hidden source")
                CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 24)])
                let box = CGRect(origin: .zero, size: size)
                manager.layers[2].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 12)
                let folder = try XCTUnwrap(manager.addFolder(name: "Hidden source scope"))
                for index in 0..<3 { manager.layers[index].parentFolderID = folder }
                let folderIndex = try XCTUnwrap(manager.folders.firstIndex { $0.id == folder })
                manager.layers[0].isVisible = !hideLayer
                manager.folders[folderIndex].isVisible = hideLayer
                manager.currentLayerIndex = 0
                manager.currentFrame = 14
                let bounds = CGRect(x: 6, y: 16, width: 20, height: 16)
                manager.selection = Selection(path: loop(bounds), bounds: bounds)
                manager.history.removeAll()
                let ids = manager.layers.map(\.id)
                let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 24))[3], 0,
                               "PREMISE: either the source layer or its containing folder is hidden")
                manager.beginDuplicate()
                XCTAssertNotNil(manager.floatingPiece, "Duplicate still admits the selected hidden source")
                guard let piece = manager.floatingPiece else { return }
                var moved = piece.transform
                moved.position.x += 12
                manager.updateFloatingPose(transform: moved, distortQuad: nil)
                XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
                let expected: [UInt8] = gradeVisible ? [64, 64, 64, 255] : [128, 128, 128, 255]
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 25, y: 24)), expected,
                               "the admitted copy reads hidden ink but respects the escaped grade's own eye")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 24))[3], 0, "the original source remains hidden")
                XCTAssertEqual(manager.layers[0].isVisible, !hideLayer)
                XCTAssertEqual(manager.folders[folderIndex].isVisible, hideLayer)
                XCTAssertEqual(manager.layers[1].isVisible, gradeVisible)
                XCTAssertTrue(manager.layers[0].cels[0].raster === sourceRaster)
                XCTAssertEqual(manager.history.undoStack.count, 1)
                let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                manager.undo()
                XCTAssertEqual(manager.layers.map(\.id), ids)
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before, "Undo restores the hidden-source picture exactly")
                manager.redo()
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after, "Redo restores the admitted copy exactly")
            }
        }
    }

    @MainActor
    func testNonRasterDuplicateKeepsItsTierReadInsteadOfCopyingAValueSheet() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for value in [false, true] {
            let manager = CanvasFixture.manager(layerCount: 0)
            if value { manager.addValueLayer(color: PaletteColor(hex: "FF0000"), name: "Value sheet") }
            else { manager.addTransformLayer(name: "Transform without pixel tiers") }
            let sourceKind = manager.layers[0].kind
            manager.currentFrame = 4
            let bounds = CGRect(x: 8, y: 8, width: 20, height: 20)
            manager.selection = Selection(path: loop(bounds), bounds: bounds)
            manager.history.removeAll()
            let ids = manager.layers.map(\.id)
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
            manager.beginDuplicate()
            XCTAssertNotNil(manager.floatingPiece, "the existing nonvector tier-copy admission remains available")
            guard manager.floatingPiece != nil else { return }
            XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
            let copied = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[manager.currentLayerIndex].cels[0],
                                                       canvasSize: CanvasFixture.canvasSize, memoize: false)?.cgImage)
            let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(copied))
            XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 0 },
                          "Value and transform sources keep their empty pixel-tier copy; no solid-sheet capture is added")
            XCTAssertEqual(manager.layers[0].kind, sourceKind)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            XCTAssertEqual(manager.layers.map(\.id), ids)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
            manager.redo()
            XCTAssertEqual(manager.layers.count, ids.count + 1)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
        }
    }

    @MainActor
    func testRasterDuplicateKeepsHigherPassThroughGradesButStopsThemAtAnIsolatedFolder() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for nested in [false, true] {
            for isolated in [false, true] {
                let manager = CanvasFixture.manager(layerCount: 1)
                let size = CanvasFixture.canvasSize
                manager.layers[0].cels[0].frameCount = 3
                manager.layers[0].cels[0].raster = try CanvasFixture.rasterTexture(
                    duplicateContributionPatch([128, 128, 128, 255], x: 10..<20, y: 20..<28), size: size, strokeCount: 1)
                manager.addLayer(name: "Other paint in the higher folder")
                manager.layers[1].cels[0].frameCount = 3
                manager.layers[1].cels[0].raster = try CanvasFixture.rasterTexture(
                    duplicateContributionPatch([0, 0, 255, 255], x: 40..<50, y: 20..<28), size: size, strokeCount: 1)
                manager.addValueLayer(effect: .brightnessContrast(.init(brightness: 0.5, contrast: 1)), name: "Higher folder grade")
                CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 24)])
                manager.addTransformLayer(name: "Repeat source and upper folder")
                CanvasFixture.setCelLayout(manager, layerIndex: 3, [(start: 0, length: 24)])
                let box = CGRect(origin: .zero, size: size)
                manager.layers[3].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 12)
                let folder = try XCTUnwrap(manager.addFolder(name: "Higher grade scope"))
                for index in 1...2 { manager.layers[index].parentFolderID = folder }
                let folderIndex = try XCTUnwrap(manager.folders.firstIndex { $0.id == folder })
                manager.folders[folderIndex].isIsolated = isolated
                if nested {
                    let outer = try XCTUnwrap(manager.addFolder(name: "Higher pass-through wrapper"))
                    let outerIndex = try XCTUnwrap(manager.folders.firstIndex { $0.id == outer })
                    manager.folders[outerIndex].isIsolated = false
                    manager.folders[folderIndex].parentFolderID = outer
                }
                manager.currentLayerIndex = 0
                manager.currentFrame = 14
                let bounds = CGRect(x: 6, y: 16, width: 48, height: 16)
                manager.selection = Selection(path: loop(bounds), bounds: bounds)
                manager.history.removeAll()
                let ids = manager.layers.map(\.id)
                let sourceIDs = manager.layers[0].cels.map(\.id)
                let source = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)))
                let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                let expected: [UInt8] = isolated ? [128, 128, 128, 255] : [64, 64, 64, 255]
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 24)), expected,
                               "PREMISE: only the pass-through folder grades the raster outside it")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 44, y: 24)), [0, 0, 128, 255],
                               "PREMISE: the higher folder also contains its own distinct painted sibling")
                manager.beginDuplicate()
                XCTAssertNotNil(manager.floatingPiece, "the outside raster contribution is admitted")
                guard let piece = manager.floatingPiece else { return }
                var moved = piece.transform
                moved.position.x += 12
                manager.updateFloatingPose(transform: moved, distortQuad: nil)
                XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 25, y: 24)), expected,
                               "the copy keeps outer-backdrop grades through pass-through wrappers and stops at isolation")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 56, y: 24))[3], 0,
                               "higher-folder paint is never copied with its grading contribution")
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 13, y: 24)), expected)
                XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 44, y: 24)), [0, 0, 128, 255])
                XCTAssertEqual(manager.layers[0].cels.map(\.id), sourceIDs)
                XCTAssertEqual(try CanvasFixture.rgbaBytes(try XCTUnwrap(manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)), source)
                XCTAssertEqual(manager.folders[folderIndex].isIsolated, isolated)
                XCTAssertEqual(manager.history.undoStack.count, 1)
                let after = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                manager.undo()
                XCTAssertEqual(manager.layers.map(\.id), ids)
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before, "Undo restores the original outer-backdrop picture exactly")
                manager.redo()
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), after, "Redo restores the copied outer-backdrop contribution exactly")
            }
        }
    }

    @MainActor
    func testRepeatedLinkedFillClearAndCutKeepTheGeneratedPictureLinkAndClipboard() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        defer { pasteboard.items = savedItems; Compositor.backend = previous }
        for sourceOnly in [false, true] {
            for action in ["Fill", "Clear", "Cut"] {
                let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
                let manager = f.manager
                let size = CanvasFixture.canvasSize
                let references = [24, 25].map { start -> Cel in
                    let cel = Cel(id: UUID(), startFrame: start, frameCount: 1,
                                  raster: .empty(size: size), vector: .empty(size: size))
                    cel.vector?.addFill(path: loop(CGRect(x: 10, y: 20, width: 10, height: 8)),
                                        color: colour(0, 0, 1))
                    return cel
                }
                manager.layers[0].cels.append(contentsOf: references)
                manager.layers[0].cels[0].interpolation = InterpolationRecipe(
                    references: references.map { InterpolationReference(layerID: manager.layers[0].id, celID: $0.id) },
                    t: 0.5)
                if sourceOnly {
                    XCTAssertTrue(manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1))
                }
                manager.brushColor = colour(0, 1, 0).color
                manager.history.removeAll()
                let before = try XCTUnwrap(CanvasFixture.rgbaBytes(memoPicture(manager)))
                let generatedPixel = try memoPixel(manager, at: CGPoint(x: 13, y: 32))
                XCTAssertTrue(generatedPixel[2] > 0 && generatedPixel[0] == 0 && generatedPixel[1] == 0
                              && generatedPixel[2] == generatedPixel[3],
                              "a real generated blue picture is shown through the document-time parent")
                let ids = manager.layers[0].cels.map(\.id)
                let ink = try manager.layers[0].cels.compactMap(\.vector).map(selectionInk)
                let recipe = try JSONEncoder().encode(manager.layers[0].cels[0].interpolation)
                pasteboard.string = "keep clipboard on refused linked edit"
                switch action {
                case "Fill": manager.fillSelection()
                case "Clear": manager.clearSelectionPixels()
                default: XCTAssertFalse(manager.cutSelectionToPasteboard(), "Cut refuses the same linked write as Clear")
                }
                XCTAssertEqual(manager.notice?.kind, .cannotEditDerivedSelection,
                               "the artist is told to choose a hand-drawn frame")
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before,
                               "refusing \(action) leaves the generated drawing exact")
                XCTAssertEqual(try JSONEncoder().encode(manager.layers[0].cels[0].interpolation), recipe,
                               "the generated link and all its settings survive")
                XCTAssertEqual(try manager.layers[0].cels.compactMap(\.vector).map(selectionInk), ink,
                               "no hidden source drawing is rewritten")
                XCTAssertEqual(manager.layers[0].cels.map(\.id), ids)
                XCTAssertEqual(manager.history.undoStack.count, 0, "refusal adds no Undo step")
                XCTAssertEqual(manager.currentFrame, 14)
                XCTAssertNotNil(manager.selection, "the artist can choose another action on the same loop")
                XCTAssertEqual(pasteboard.string, "keep clipboard on refused linked edit",
                               "Cut does not publish a clipboard result before write admission")
                let copiedPicture = manager.copySelectionToPasteboard()
                XCTAssertTrue(copiedPicture, "Copy may copy the generated picture without changing its link")
                XCTAssertNotNil(pasteboard.image?.cgImage, "Copy publishes an actual clipboard picture")
                guard copiedPicture, let copied = pasteboard.image?.cgImage else { return }
                XCTAssertEqual(try CanvasFixture.rgbaBytes(copied),
                               try clipboardCropBytes(memoPicture(manager), rect: try XCTUnwrap(manager.selection).bounds))
                XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), before)
                XCTAssertEqual(manager.history.undoStack.count, 0)
            }
        }
    }

    /// Independent integer crop of compositor bytes, not the UIKit crop used by Copy.
    private func clipboardCropBytes(_ image: CGImage, rect: CGRect) throws -> [UInt8] {
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(image))
        return (Int(rect.minY)..<Int(rect.maxY)).flatMap { y in
            let start = (y * image.width + Int(rect.minX)) * 4
            return Array(bytes[start..<(start + Int(rect.width) * 4)])
        }
    }

    @MainActor
    func testRepeatedCopyWritesActualShownPixelsWithSourceChannelsAndContainerOnlyBacking() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        defer { pasteboard.items = savedItems; Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            if sourceOnly {
                manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1)
                manager.layers[0].cels[1].vector?.addFill(path: loop(CGRect(x: 0, y: 0, width: 64, height: 64)), color: colour(1, 0, 0))
            }
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                CanvasFixture.solidImage(.red, rect: CGRect(x: 10, y: 10, width: 10, height: 8)))
            let rect = CGRect(x: 6, y: 6, width: 50, height: 44)
            manager.selection = Selection(path: loop(rect), bounds: rect)
            manager.history.removeAll()
            let original = try selectionInk(f.vector)
            let picture = try memoPicture(manager)
            let expected = try clipboardCropBytes(picture, rect: rect)
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 22))[0], 200,
                                 "PREMISE: backing follows only the document-time parent")
            XCTAssertGreaterThan(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[2], 100,
                                 "PREMISE: native blue follows source cel/group plus document parent")
            pasteboard.image = CanvasFixture.solidImage(.magenta,
                rect: CGRect(origin: .zero, size: rect.size), size: rect.size)
            XCTAssertTrue(manager.copySelectionToPasteboard())
            let copied = try XCTUnwrap(pasteboard.image?.cgImage, "Copy must publish an actual clipboard image")
            XCTAssertEqual(copied.width, 50)
            XCTAssertEqual(copied.height, 44)
            XCTAssertEqual(CanvasFixture.rgbaBytes(copied), expected,
                           "actual clipboard pixels match the shown source including independently placed backing and ink")
            XCTAssertEqual(try selectionInk(f.vector), original, "Copy does not rewrite source ink")
            XCTAssertEqual(manager.history.undoStack.count, 0)
            XCTAssertEqual(manager.currentFrame, 14)
        }
    }

    @MainActor
    func testRepeatedCutCopiesAndClearsTheSameShownSourceAsOneUndoStep() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        defer { pasteboard.items = savedItems; Compositor.backend = previous }
        for sourceOnly in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: sourceOnly)
            let manager = f.manager
            if sourceOnly {
                manager.addCel(layerIndex: 0, startFrame: 14, frameCount: 1)
                manager.layers[0].cels[1].vector?.addFill(path: loop(CGRect(x: 0, y: 0, width: 64, height: 64)), color: colour(1, 0, 0))
            }
            let sourceID = manager.layers[0].cels[0].id
            let original = try selectionInk(f.vector)
            let rawBefore = sourceOnly ? try selectionInk(XCTUnwrap(manager.layers[0].cels[1].vector)) : nil
            let rect = try XCTUnwrap(manager.selection?.bounds)
            let before = try memoPicture(manager)
            let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(before))
            let expected = try clipboardCropBytes(before, rect: rect)
            manager.history.removeAll()
            pasteboard.image = CanvasFixture.solidImage(.magenta,
                rect: CGRect(origin: .zero, size: rect.size), size: rect.size)
            XCTAssertTrue(manager.cutSelectionToPasteboard())
            let copied = try XCTUnwrap(pasteboard.image?.cgImage)
            XCTAssertEqual(CanvasFixture.rgbaBytes(copied), expected,
                           "Cut puts the shown source pixels on the actual clipboard before clearing them")
            XCTAssertEqual(f.vector.elements.map(\.id), [f.red], "Cut clears only the shown blue source mark")
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[3], 0, "the copied blue mark is visibly gone")
            XCTAssertEqual(manager.layers[0].cels[0].id, sourceID)
            if let rawBefore {
                XCTAssertEqual(try selectionInk(XCTUnwrap(manager.layers[0].cels[1].vector)), rawBefore,
                               "Cut leaves the raw-time other drawing unchanged")
            }
            XCTAssertEqual(manager.history.undoStack.count, 1, "copy plus clear is one artwork Undo")
            XCTAssertEqual(manager.currentFrame, 14)
            manager.undo()
            XCTAssertEqual(try selectionInk(f.vector), original)
            XCTAssertEqual(try CanvasFixture.rgbaBytes(memoPicture(manager)), pixels)
            manager.redo()
            XCTAssertEqual(try memoPixel(manager, at: CGPoint(x: 15, y: 36))[3], 0)
            XCTAssertEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(pasteboard.image?.cgImage)), expected,
                           "Undo and Redo leave the successful clipboard result intact")
        }
    }

    @MainActor
    func testFailedRequiredCopyPreservesClipboardSourceAndHistoryForCopyAndCut() throws {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        defer { pasteboard.items = savedItems }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("repeat-clipboard-refusal-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = RasterResidency(budgetBytes: 64 * 64 * 4 * 8, hasHeadroom: { _ in true })
        let png = root.appendingPathComponent("owned-fixture.png")
        try XCTUnwrap(CanvasFixture.solidImage(.red, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)).pngData()).write(to: png)
        let backing = try ProjectStore.RasterBacking.protect(png, using: owner).get()
        let unreadable = RasterSource.backed(by: backing, using: owner)
        // The existing protected-backing failure fixture: no project or original artwork is touched.
        try FileManager.default.removeItem(at: backing.url)
        for cutting in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: true)
            let manager = f.manager
            manager.layers[0].cels[0].bakedImage = unreadable
            let original = try selectionInk(f.vector)
            pasteboard.image = CanvasFixture.solidImage(.magenta, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize))
            let sentinel = try XCTUnwrap(CanvasFixture.rgbaBytes(XCTUnwrap(pasteboard.image?.cgImage)))
            XCTAssertNil(PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize),
                         "PREMISE: required unreadable backing refuses the real flattened picture")
            let copied = cutting ? manager.cutSelectionToPasteboard() : manager.copySelectionToPasteboard()
            XCTAssertFalse(copied, "required render refusal is a failed Copy, so Cut cannot clear")
            XCTAssertEqual(try selectionInk(f.vector), original, "failed Copy never deletes source ink")
            XCTAssertTrue(manager.layers[0].cels[0].bakedImage === unreadable)
            XCTAssertEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(pasteboard.image?.cgImage)), sentinel,
                           "failed Copy leaves the actual prior clipboard image intact")
            XCTAssertEqual(manager.history.undoStack.count, 0, "failed Copy or Cut records no artwork step")
            XCTAssertEqual(manager.currentFrame, 14)
        }
    }

    @MainActor
    func testRepeatClipboardSettlesTheEarlierSelectionEditBeforeCopyOrCut() throws {
        let pasteboard = UIPasteboard.general
        let savedItems = pasteboard.items
        defer { pasteboard.items = savedItems }
        for cutting in [false, true] {
            let f = try repeatedSelectionFixture(sourceOnly: true)
            let manager = f.manager
            XCTAssertTrue(manager.beginSelectionEdit(.color))
            manager.previewSelectionEdit(.color(colour(0, 1, 0)))
            XCTAssertEqual(f.vector.elements.first { $0.id == f.blue }?.stroke?.color, colour(0, 0, 1),
                           "PREMISE: the green edit is still held, not committed to source ink")
            XCTAssertEqual(manager.history.undoStack.count, 0)
            XCTAssertTrue(cutting ? manager.cutSelectionToPasteboard() : manager.copySelectionToPasteboard())
            let copied = try XCTUnwrap(pasteboard.image?.cgImage)
            let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(copied))
            let offset = (10 * copied.width + 9) * 4 // source(15,36) minus crop origin(6,26)
            XCTAssertGreaterThan(bytes[offset + 1], 100, "the actual clipboard receives the earlier edit's settled half-opacity green")
            XCTAssertEqual(bytes[offset + 2], 0)
            XCTAssertNil(manager.selectionEdit)
            XCTAssertEqual(manager.history.undoStack.count, cutting ? 2 : 1,
                           "the prior colour gesture keeps its step, and Cut adds exactly one")
            if cutting {
                XCTAssertEqual(f.vector.elements.map(\.id), [f.red])
                manager.undo()
            }
            XCTAssertEqual(f.vector.elements.first { $0.id == f.blue }?.stroke?.color, colour(0, 1, 0))
            manager.undo()
            XCTAssertEqual(f.vector.elements.first { $0.id == f.blue }?.stroke?.color, colour(0, 0, 1))
            XCTAssertEqual(manager.currentFrame, 14)
        }
    }

    // MARK: - The readout

    /// **The swatch defaults to the selection's colour, and a mixed loop opens on the most common.**
    /// Two black strokes and a red one: black, and Mixed. The red one alone: red, and not mixed. A
    /// loop around a photograph: no colour at all.
    ///
    /// Mutation caught: returning `order.first` from `SelectionStyle.of`'s `mode` instead of the
    /// most common turns the two-black-one-red loop red when the red stroke is first in the list —
    /// the fixture below puts it first for exactly that reason.
    func testTheSwatchDefaultsToTheSelectionsColourAndAMixedLoopOpensOnTheMostCommon() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 10, size: 9, opacity: 0.5, colour: colour(1, 0, 0)))
        vector.addStroke(stroke(y: 20, size: 4, opacity: 1))
        vector.addStroke(stroke(y: 30, size: 4, opacity: 1))

        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 36)))
        var style = manager.selectionStyle
        XCTAssertEqual(style.color, colour(0, 0, 0), "two of three are black, so the swatch opens on black")
        XCTAssertTrue(style.colorIsMixed, "and says the loop holds more than one colour")
        XCTAssertEqual(style.size, 4, "two of three are 4 pt")
        XCTAssertTrue(style.sizeIsMixed)
        XCTAssertEqual(style.opacity, 1)
        XCTAssertTrue(style.opacityIsMixed)

        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 14)))
        style = manager.selectionStyle
        XCTAssertEqual(style.color, colour(1, 0, 0), "the red stroke alone: red")
        XCTAssertFalse(style.colorIsMixed, "and not mixed")
        XCTAssertEqual(style.size, 9)
        XCTAssertFalse(style.sizeIsMixed)
        XCTAssertEqual(style.opacity, 0.5)

        vector.addImage(VectorImageElement(source: try CanvasFixture.placedSource(CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6))),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 52),
                                                                     scale: 1, rotation: 0)))
        select(manager, layerIndex, loop(CGRect(x: 20, y: 44, width: 24, height: 18)))
        style = manager.selectionStyle
        XCTAssertNil(style.color, "a loop around a photograph has no colour to default to")
        XCTAssertNil(style.size)
        XCTAssertNil(style.opacity)

        manager.selection = nil
        XCTAssertEqual(manager.selectionStyle, .unavailable, "no selection, nothing to show")
    }

    /// **Mid-drag the readout is the live value, and it touches no geometry**: the tally is over the
    /// session's own list, so it is the value every caught element already holds.
    func testTheReadoutDuringADragIsTheLiveValueAndIsNoLongerMixed() {
        let (manager, _, _, _, _) = threeStrokes()
        XCTAssertTrue(manager.selectionStyle.sizeIsMixed, "4 and 6 pt: mixed before the drag")
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(20))
        let style = manager.selectionStyle
        XCTAssertEqual(style.size, 20, "the slider shows what the finger set")
        XCTAssertFalse(style.sizeIsMixed, "and the first tick made the loop agree")
        XCTAssertTrue(style.opacityIsMixed, "the other control's readout is untouched by this drag")
        manager.cancelSelectionEdit()
        XCTAssertTrue(manager.selectionStyle.sizeIsMixed, "cancelled: mixed again")
    }

    // MARK: - One drag, one step

    /// **A ten-tick drag is one undo step, and one `undo()` puts every stroke's own width back.**
    /// The two caught strokes start at *different* sizes, so "restores the original" is a claim about
    /// each rather than about a shared number.
    ///
    /// Mutation caught: registering a step per tick (calling `commitSelectionEdit()` then
    /// `beginSelectionEdit` inside `previewSelectionEdit`) makes `stepsSince` read 10 and one undo
    /// restore only the ninth tick's sizes.
    func testATenTickDragIsOneUndoStepAndOneUndoRestoresEveryStrokesOwnSize() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        let before = sizes(vector)
        XCTAssertEqual(before, [4, 6, 8])

        XCTAssertTrue(manager.beginSelectionEdit(.size))
        let version = vector.version
        for tick in 1...10 {
            manager.previewSelectionEdit(.size(CGFloat(10 + tick)))
            XCTAssertEqual(stepsSince(baseline, manager), 0, "tick \(tick) recorded a step")
            XCTAssertEqual(shownSizes(manager, vector), [CGFloat(10 + tick), CGFloat(10 + tick), 8],
                           "tick \(tick) is what the canvas shows — the preview is live, not deferred")
            XCTAssertEqual(sizes(vector), before, "tick \(tick) wrote the document")
            XCTAssertEqual(vector.version, version, "tick \(tick) moved the canvas's version")
        }
        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 1, "ten ticks, one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .resizeSelectionStrokes)
        XCTAssertEqual(sizes(vector), [20, 20, 8])

        manager.undo()
        XCTAssertEqual(sizes(vector), before, "one undo puts 4 and 6 back — each its own, not one shared width")
        manager.redo()
        XCTAssertEqual(sizes(vector), [20, 20, 8], "and one redo brings the drag's end back")
    }

    /// **A slider grabbed without a session open still previews and still commits once**: the first
    /// value write can land before `onEditingChanged(true)`, so `previewSelectionEdit` opens the
    /// session and the touch-down's `beginSelectionEdit` finds it open for the same control.
    func testAPreviewWithNoSessionOpenBeginsOneAndTheTouchDownReusesIt() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        manager.previewSelectionEdit(.opacity(0.3))
        XCTAssertTrue(manager.beginSelectionEdit(.opacity), "the touch-down lands on the open session")
        manager.previewSelectionEdit(.opacity(0.2))
        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 1)
        XCTAssertEqual(manager.history.undoStack.last?.label, .changeSelectionOpacity)
        XCTAssertEqual(opacities(vector), [0.2, 0.2, 0.8])
    }

    /// **Switching controls mid-drag commits the first drag and opens the second** — two steps, in
    /// order, rather than one step that mixes a size with an opacity.
    func testASecondControlMidSessionCommitsTheFirstAsItsOwnStep() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(15))
        manager.previewSelectionEdit(.opacity(0.5))
        XCTAssertEqual(stepsSince(baseline, manager), 1, "the size drag closed when the opacity one began")
        XCTAssertEqual(manager.history.undoStack.last?.label, .resizeSelectionStrokes)
        XCTAssertTrue(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 2)
        XCTAssertEqual(manager.history.undoStack.last?.label, .changeSelectionOpacity)
        XCTAssertEqual(sizes(vector), [15, 15, 8])
        XCTAssertEqual(opacities(vector), [0.5, 0.5, 0.8])
    }

    // MARK: - Nothing changed, nothing recorded

    /// **A drag that ends where it began records nothing**, and under Cut it throws the split away:
    /// the list the artist is left with is the list they started with, element for element.
    ///
    /// Mutation caught: comparing the *lists* rather than the fields in `commitSelectionEdit` — under
    /// Cut they always differ by the split, so a drag back to the start value would record a step
    /// whose only content is a cut the artist never asked for.
    func testADragThatEndsWhereItBeganRecordsNothingAndUnderCutThrowsTheSplitAway() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 20, size: 6))
        let originalID = vector.elements[0].id
        let baseline = manager.history.undoStack.count
        // x ≥ 30: the stroke straddles the loop, so Cut splits it into two.
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertEqual(manager.selectionMembership, .cutting, "fixture: the default rule cuts")

        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(20))
        XCTAssertEqual(shown(manager, vector).count, 2, "mid-drag the stroke is split and the inside piece is 20 pt")
        XCTAssertEqual(Set(shownSizes(manager, vector)), [6, 20])
        XCTAssertEqual(vector.elements.count, 1, "and none of it is in the document yet")
        manager.previewSelectionEdit(.size(6))
        XCTAssertFalse(manager.commitSelectionEdit(), "back at 6 pt: nothing to record")
        XCTAssertEqual(stepsSince(baseline, manager), 0)
        XCTAssertEqual(vector.elements.count, 1, "and the split is gone")
        XCTAssertEqual(vector.elements[0].id, originalID, "the stroke is the artist's own again")
        XCTAssertEqual(sizes(vector), [6])
    }

    /// **A picker opened and closed untouched leaves no trace** — no step, no render, no version bump.
    func testASessionOpenedAndClosedWithoutATickLeavesNoTrace() {
        let (manager, _, vector, _, _) = threeStrokes()
        let baseline = manager.history.undoStack.count
        let version = vector.version
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        XCTAssertFalse(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 0)
        XCTAssertEqual(vector.version, version, "nothing was assigned, so nothing has to redraw")

        // And a first tick that changes nothing — the picker opened on the selection's own colour —
        // assigns nothing either.
        XCTAssertTrue(manager.beginSelectionEdit(.color))
        manager.previewSelectionEdit(.color(colour(0, 0, 0)))
        XCTAssertEqual(vector.version, version, "a tick at the current value is not an edit")
        XCTAssertFalse(manager.commitSelectionEdit())
        XCTAssertEqual(stepsSince(baseline, manager), 0)
    }

    // MARK: - Cancel

    /// **Cancel puts the pre-drag list back with no entry** — by the call, by the selection being
    /// cleared mid-drag, and by undo pressed mid-drag, which then undoes the *previous* step.
    ///
    /// Mutation caught: `cancelSelectionEdit` dropping the session and leaving the window up
    /// (`revertElementEdit` not ending the live edit) leaves the last tick's sizes on screen — the
    /// `shownSizes` assertion after each cancel goes red.
    func testCancelRestoresThePreDragStateWithNoEntryHoweverItIsReached() {
        let (manager, _, vector, _, _) = threeStrokes()
        // One real step to undo past, so the mid-drag undo below has something to land on.
        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.9)))
        let baseline = manager.history.undoStack.count
        let before = sizes(vector)

        // 1. The call.
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(30))
        XCTAssertEqual(shownSizes(manager, vector), [30, 30, 8])
        manager.cancelSelectionEdit()
        XCTAssertEqual(shownSizes(manager, vector), before, "cancel: the sizes the artist started with")
        XCTAssertEqual(sizes(vector), before, "and the document is what it was")
        XCTAssertNil(manager.liveCelContentEdit, "and the window is gone")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and no step")
        XCTAssertNil(manager.selectionEdit)

        // 2. The selection cleared under the finger.
        XCTAssertTrue(manager.beginSelectionEdit(.size))
        manager.previewSelectionEdit(.size(31))
        manager.deselect()
        XCTAssertEqual(shownSizes(manager, vector), before, "deselect mid-drag: the sizes the artist started with")
        XCTAssertEqual(stepsSince(baseline, manager), 1, "the Deselect is the one step, and the cancelled drag added none")
        XCTAssertNil(manager.selectionEdit, "the session is closed, not merely detached from its loop")
        manager.previewSelectionEdit(.size(32))
        XCTAssertEqual(sizes(vector), before, "a tick with no selection has nothing to be about")

        // 3. Undo under the finger: the drag is discarded and the press undoes the opacity step.
        let (manager2, _, vector2, _, _) = threeStrokes()
        XCTAssertTrue(manager2.applySelectionEdit(.opacity(0.9)))
        XCTAssertEqual(opacities(vector2), [0.9, 0.9, 0.8])
        XCTAssertTrue(manager2.beginSelectionEdit(.size))
        manager2.previewSelectionEdit(.size(33))
        XCTAssertEqual(shownSizes(manager2, vector2), [33, 33, 8], "the drag is on screen")
        manager2.undo()
        XCTAssertEqual(sizes(vector2), [4, 6, 8], "undo mid-drag: the drag is thrown away")
        XCTAssertEqual(opacities(vector2), [0.4, 0.6, 0.8], "and the press undid the step before it")
        XCTAssertNil(manager2.selectionEdit)
    }

    // MARK: - Per kind

    /// **Fills and text take colour and opacity; images and videos take nothing; size reaches only
    /// strokes.** `SelectionEditKind`'s table, pinned row by row. Under Touching so that no kind is
    /// cut and each element keeps its id through all three edits.
    ///
    /// Mutation caught: adding a `(.size, .fill)` arm to `rewritten` that wrote `fill.opacity` (the
    /// nearest field a fill has) reddens the fill's size row; dropping the `.paint` guard from the
    /// colour arm reddens the eraser row.
    func testFillsAndTextTakeColourAndOpacityImagesAndVideosTakeNothingAndSizeReachesOnlyStrokes() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 8, size: 4, opacity: 0.5))
        vector.addStroke(stroke(y: 14, size: 5, opacity: 0.5, composite: .erase))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 12, y: 20, width: 20, height: 6), transform: nil),
                                         color: colour(0, 0, 1, 0.25), opacity: 0.5))
        var recipe = TextRecipe(string: "hi")
        recipe.opacity = 0.7
        recipe.color = colour(0, 0, 0, 0.4)
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 22, y: 30),
                                                             size: CGSize(width: 12, height: 8))))
        vector.addImage(VectorImageElement(source: try CanvasFixture.placedSource(CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6))),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 44),
                                                                     scale: 1, rotation: 0)))
        var video = VectorVideoElement(assetURL: URL(fileURLWithPath: "/dev/null"),
                                       assetFileName: "null", naturalSize: CGSize(width: 8, height: 4),
                                       sourceStart: .zero, sourceEnd: SourceTime(value: 1, timescale: 1),
                                       speed: 1,
                                       transform: LayerTransform(position: CGPoint(x: 30, y: 54),
                                                                 scale: 1, rotation: 0))
        video.displayFrame = CanvasFixture.solidImage(.blue, rect: CGRect(x: 0, y: 0, width: 8, height: 4),
                                                      size: CGSize(width: 8, height: 4))
        vector.elements.append(.video(video))
        vector.bumpVersion()
        let ids = vector.elements.map(\.id)

        select(manager, layerIndex, loop(CGRect(x: 2, y: 2, width: 60, height: 60)))
        manager.setSelectionMembership(.touching)
        let baseline = manager.history.undoStack.count

        XCTAssertTrue(manager.applySelectionEdit(.color(colour(1, 0, 0))))
        XCTAssertTrue(manager.applySelectionEdit(.size(11)))
        XCTAssertTrue(manager.applySelectionEdit(.opacity(0.3)))
        XCTAssertEqual(stepsSince(baseline, manager), 3)
        XCTAssertEqual(vector.elements.map(\.id), ids, "Touching: every element keeps its id and its place")

        // Looked up by kind rather than by index: `addImage` and `addFill` place their elements by
        // their own rules, and this test is about what each kind takes, not where it sits.
        let strokes = vector.elements.compactMap(\.stroke)
        guard let paint = strokes.first(where: { $0.composite == .paint }),
              let eraser = strokes.first(where: { $0.composite == .erase }),
              let fill = vector.elements.compactMap(\.fill).first,
              let text = vector.elements.compactMap(\.text).first,
              let image = vector.elements.compactMap(\.image).first,
              let placedVideo = vector.elements.compactMap(\.video).first else {
            return XCTFail("fixture: one element of every kind")
        }
        XCTAssertEqual(paint.color, colour(1, 0, 0), "paint stroke: colour")
        XCTAssertEqual(paint.size, 11, "paint stroke: size")
        XCTAssertEqual(paint.opacity, 0.3, "paint stroke: opacity")

        XCTAssertEqual(eraser.color, colour(0, 0, 0), "eraser: no colour — a punch reads only alpha")
        XCTAssertEqual(eraser.size, 11, "eraser: size, because the hole's width is visible")
        XCTAssertEqual(eraser.opacity, 0.3, "eraser: opacity, because how much it removes is visible")

        XCTAssertEqual(fill.solidColor, colour(1, 0, 0, 0.25), "fill: the hue, keeping its own alpha")
        XCTAssertEqual(fill.opacity, 0.3, "fill: opacity")

        XCTAssertEqual(text.recipe.color, colour(1, 0, 0, 0.4), "text: the hue, keeping its own alpha")
        XCTAssertEqual(text.recipe.opacity, 0.3, "text: opacity")
        XCTAssertEqual(text.recipe.typography.pointSize, recipe.typography.pointSize,
                       "text: size is the strokes' width, not the type size — untouched")

        XCTAssertEqual(image.transform, LayerTransform(position: CGPoint(x: 30, y: 44), scale: 1, rotation: 0),
                       "image: nothing, from any of the three")
        XCTAssertEqual(placedVideo.transform, LayerTransform(position: CGPoint(x: 30, y: 54), scale: 1, rotation: 0),
                       "video: nothing, from any of the three")

        // And a loop that catches only the two kinds that take nothing is refused as "nothing to do":
        // no step, and the one-shot says so.
        select(manager, layerIndex, loop(CGRect(x: 20, y: 40, width: 24, height: 20)))
        XCTAssertFalse(manager.applySelectionEdit(.color(colour(0, 1, 0))), "a photo and a video: nothing changed")
        XCTAssertFalse(manager.applySelectionEdit(.size(3)))
        XCTAssertFalse(manager.applySelectionEdit(.opacity(0.1)))
        XCTAssertEqual(stepsSince(baseline, manager), 3, "and nothing recorded")
    }

    /// **Under Cut only the inside piece takes the size, and one undo puts the whole stroke back.**
    /// The split and the rewrite go through one seam and one step, as a recolour under Cut already does.
    func testUnderCutOnlyTheInsidePieceTakesTheSizeAndUndoRestoresTheWholeStroke() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(y: 20, size: 6))
        let originalID = vector.elements[0].id
        let baseline = manager.history.undoStack.count
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))

        XCTAssertTrue(manager.applySelectionEdit(.size(20)))
        XCTAssertEqual(vector.elements.count, 2, "Cut: the straddling stroke is two strokes")
        let inside = vector.elements.compactMap(\.stroke).first { $0.size == 20 }
        let outside = vector.elements.compactMap(\.stroke).first { $0.size == 6 }
        XCTAssertNotNil(inside, "the inside piece is 20 pt")
        XCTAssertNotNil(outside, "the outside piece keeps 6 pt")
        XCTAssertTrue(inside!.samples.positions.allSatisfy { $0.x >= 29.5 }, "and the 20 pt piece is the one inside the loop")
        XCTAssertEqual(stepsSince(baseline, manager), 1)

        manager.undo()
        XCTAssertEqual(vector.elements.count, 1, "undo: one stroke again")
        XCTAssertEqual(vector.elements[0].id, originalID)
        XCTAssertEqual(sizes(vector), [6])
    }

    // MARK: - Refusals

    /// The band refuses on a pixel cel and on an in-between, and says which control it is about.
    func testTheBandRefusesOnAPixelCelAndSaysWhy() {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertEqual(manager.layers[manager.currentLayerIndex].kind, .raster, "fixture: a pixel layer")
        manager.selection = Selection(path: loop(CGRect(x: 2, y: 2, width: 20, height: 20)),
                                      bounds: CGRect(x: 2, y: 2, width: 20, height: 20))
        let reason = manager.selectionEditUnavailableReason
        XCTAssertNotNil(reason, "a pixel cel must say why")
        XCTAssertTrue(reason?.contains("vector layers only") == true, "…in the artist's terms: \(reason ?? "")")
        XCTAssertTrue(reason?.contains("Colour") == true && reason?.contains("Size") == true
                      && reason?.contains("Opacity") == true,
                      "…naming the controls it is about, not a feature name nobody can see: \(reason ?? "")")
        XCTAssertFalse(manager.beginSelectionEdit(.size), "and the session refuses")
        XCTAssertEqual(manager.selectionStyle, .unavailable)
    }
}
