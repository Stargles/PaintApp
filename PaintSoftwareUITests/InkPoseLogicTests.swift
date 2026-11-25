import XCTest
import SwiftUI
import UIKit
import CoreGraphics

/// **What is drawn on a layer lands where it was drawn, whatever poses the layer** — TODO (124):
///
/// > *"put a move layer on top of a normal vector layer. When the user lays down a stroke, that stroke
/// > does not get put down where the user wants it, because the move layer on top moves it in
/// > compositing. Make it so the stroke the user lays down is properly transformed so whatever they
/// > draw accurately reflects the position the stroke gets set in."*
///
/// `CanvasManager.inkPose(forLayerID:)` is the one answer every input surface reads, so the first
/// half of this file pins that it *is* the map the canvas shows the layer through — the render walk's
/// container pose for one, two stacked and a Parallax layer, with the cel's own channel composed
/// under it — and the second half drives each tool's own commit through it and asks where the result
/// is **shown**, i.e. the stored geometry posed back through the render's own composition
/// (`posed(_:through:inheriting:)`). Each of those goes red if its pull-back is deleted, because the
/// stored geometry is then shown a pose away from where it was made. `StrokeCanvasView`, which is not
/// in this target, is driven by `InkUnderTransformUITests`.
@MainActor
final class InkPoseLogicTests: XCTestCase {

    private static let size = CGSize(width: 256, height: 256)
    private static var box: CGRect { CGRect(origin: .zero, size: size) }

    /// A vector layer (index 0, active) under one transformation layer posed by `transform`.
    private func layerUnderMove(_ transform: CGAffineTransform,
                                mode: TransformLayerMode = .move) -> (manager: CanvasManager, ink: Int) {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: transform), mode: mode)
        manager.currentLayerIndex = 0
        return (manager, 0)
    }

    private func assertSame(_ a: CGPoint?, _ b: CGPoint, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("no point: \(message)", file: file, line: line) }
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, message, file: file, line: line)
    }

    /// Where the canvas shows `element` of the active layer's cel: the render's own composition.
    private func shown(_ element: VectorElement, in manager: CanvasManager, layer: Int) -> VectorElement {
        let cel = manager.layers[layer].cels[0]
        let walk = manager.renderTreeAndPoses(atFrame: manager.currentFrame)
        let mappings = CanvasManager.poseMappings(cel.transformTracks,
                                                  atCelLocalFrame: manager.currentFrame - cel.startFrame)
        return CanvasManager.posed([element], through: mappings, inheriting: walk.poses[layer])[0]
    }

    // MARK: - The map

    func testALayerNothingPosesTakesInkAtRest() {
        let manager = CanvasManager()
        manager.canvasSize = Self.size
        manager.addVectorLayer()
        XCTAssertNil(manager.inkPose(forLayerID: manager.layers[0].id))
    }

    /// The render walk's own container pose, read rather than recomputed, and its inverse is the
    /// map from where the pen is to where the ink is stored.
    func testAMoveLayerAboveIsTheMapTheInkIsShownThrough() {
        let fx = layerUnderMove(CGAffineTransform(translationX: 40, y: -12))
        let pose = fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id)
        XCTAssertEqual(pose, fx.manager.layerPoses(atFrame: 0)[fx.ink], "not the render's own map")
        assertSame(pose?.inverse?.applied(to: CGPoint(x: 100, y: 100)), CGPoint(x: 60, y: 112),
                   "the pen's point is not pulled back to where the ink has to be stored")
    }

    /// **The pull-back family answers a point and a path the way it answers an element**: through the
    /// inverse of the pose the layer is shown through — and with the point or path itself where nothing
    /// poses the layer, or where the pose cannot be inverted (a layer collapsed to a line).
    func testThePullBackFamilyCarriesAPointAndAPathBackThroughTheInverse() {
        let fx = layerUnderMove(CGAffineTransform(translationX: 40, y: -12))
        let id = fx.manager.layers[fx.ink].id
        let square = CGPath(rect: CGRect(x: 100, y: 100, width: 10, height: 10), transform: nil)

        assertSame(fx.manager.layerSpacePoint(CGPoint(x: 100, y: 100), forLayerID: id), CGPoint(x: 60, y: 112),
                   "the pen's point is not pulled back to where the ink is stored")
        let pulled = fx.manager.layerSpacePath(square, forLayerID: id).boundingBox
        assertSame(pulled.origin, CGPoint(x: 60, y: 112), "the loop is not pulled back to the stored ink")
        XCTAssertEqual(pulled.size, CGSize(width: 10, height: 10))

        let bare = CanvasManager()
        bare.canvasSize = Self.size
        bare.addVectorLayer()
        let bareID = bare.layers[0].id
        assertSame(bare.layerSpacePoint(CGPoint(x: 100, y: 100), forLayerID: bareID), CGPoint(x: 100, y: 100),
                   "nothing poses this layer, so the point is already in its space")
        XCTAssertEqual(bare.layerSpacePath(square, forLayerID: bareID).boundingBox, square.boundingBox)

        let collapsed = PoseMap.affine(CGAffineTransform(scaleX: 0, y: 0))
        assertSame(CanvasManager.layerSpacePoint(CGPoint(x: 5, y: 5), shownThrough: collapsed), CGPoint(x: 5, y: 5),
                   "a pose that cannot be inverted leaves the point where it is")
    }

    func testStrictPathPullBackRefusesSingularAndUnmappablePosesWithoutChangingTheFallback() throws {
        let path = CGPath(rect: CGRect(x: 32, y: 8, width: 8, height: 8), transform: nil)
        XCTAssertEqual(CanvasManager.layerSpacePathIfInvertible(path, shownThrough: nil)?.boundingBoxOfPath, path.boundingBoxOfPath)
        let slide = PoseMap.affine(CGAffineTransform(translationX: 12, y: 8))
        XCTAssertEqual(CanvasManager.layerSpacePathIfInvertible(path, shownThrough: slide)?.boundingBoxOfPath,
                       CGRect(x: 20, y: 0, width: 8, height: 8))
        let singular = PoseMap.affine(CGAffineTransform(scaleX: 0, y: 0))
        let horizon = PoseMap.projective(Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: 1 / 32, h: 0, i: 1))
        for pose in [singular, horizon] {
            XCTAssertNil(CanvasManager.layerSpacePathIfInvertible(path, shownThrough: pose))
            XCTAssertEqual(CanvasManager.layerSpacePath(path, shownThrough: pose).boundingBoxOfPath, path.boundingBoxOfPath,
                           "existing selection consumers keep their documented fallback")
        }
        let crossed = CGPath(rect: CGRect(x: 24, y: 8, width: 16, height: 8), transform: nil)
        XCTAssertNil(CanvasManager.layerSpacePathIfInvertible(crossed, shownThrough: horizon))
        XCTAssertEqual(CanvasManager.layerSpacePath(crossed, shownThrough: horizon).boundingBoxOfPath, crossed.boundingBoxOfPath,
                       "the nonoptional API retains its original-path fallback for a refused crossing")
    }

    /// **Two transformation layers stacked**: the lower one moves the ink and the upper one carries
    /// the result — inner first. A turn and a slide do not commute, so the reversed order maps the
    /// test point somewhere else entirely.
    func testTwoStackedTransformLayersComposeInnerFirst() {
        let manager = CanvasManager()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "ink")
        manager.addTransformLayer(name: "lower")
        manager.addTransformLayer(name: "upper")
        XCTAssertEqual(manager.layers.map(\.name), ["ink", "lower", "upper"], "the fixture's premise")
        let slide = CGAffineTransform(translationX: 30, y: 0)
        let turn = CGAffineTransform(translationX: 128, y: 128).rotated(by: .pi / 2)
            .translatedBy(x: -128, y: -128)
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: slide), mode: .move)
        manager.layers[2].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: turn), mode: .move)
        let pose = manager.inkPose(forLayerID: manager.layers[0].id)
        let p = CGPoint(x: 10, y: 20)
        assertSame(pose?.applied(to: p), p.applying(slide).applying(turn),
                   "the lower layer's slide is not applied before the upper layer's turn")
        assertSame(pose?.inverse?.applied(to: pose?.applied(to: p) ?? .zero), p, "no round trip")
    }

    /// **Parallax gives each item its own share**, so the ink map is per layer: the item nearest the
    /// parallax layer takes all of a 100-point move and the one beneath it half (two items).
    func testParallaxHandsEachLayerItsOwnShareOfTheMove() {
        let manager = CanvasManager()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "ink")
        manager.addVectorLayer(name: "front")
        manager.addTransformLayer(name: "move")
        XCTAssertEqual(manager.layers.map(\.name), ["ink", "front", "move"], "the fixture's premise")
        manager.layers[2].transform = LayerPose(pose: PoseQuad(box: Self.box,
                                                               mappedBy: CGAffineTransform(translationX: 100, y: 0)),
                                                mode: .parallax)
        let back = manager.inkPose(forLayerID: manager.layers[0].id)?.affine
        let front = manager.inkPose(forLayerID: manager.layers[1].id)?.affine
        XCTAssertEqual(front?.tx ?? 0, 100, accuracy: 1e-9, "the nearest item takes the whole move")
        XCTAssertEqual(back?.tx ?? 0, 50, accuracy: 1e-9, "the item behind takes its own share")
    }

    /// **The cel's own channel composes under the container pose** — the order `posed` uses for an
    /// element no group claims, which is every mark not drawn yet.
    func testTheCelChannelIsAppliedBeforeTheContainerPose() {
        let fx = layerUnderMove(CGAffineTransform(translationX: 0, y: 25))
        let celTurn = CGAffineTransform(translationX: 128, y: 128).rotated(by: .pi / 2)
            .translatedBy(x: -128, y: -128)
        fx.manager.layers[fx.ink].cels[0].transformTracks[TransformChannelID.cel.id] =
            CanvasFixture.poseTrack([(0, PoseQuad(box: Self.box, mappedBy: celTurn))])
        let pose = fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id)
        let p = CGPoint(x: 10, y: 20)
        assertSame(pose?.applied(to: p), p.applying(celTurn).applying(CGAffineTransform(translationX: 0, y: 25)),
                   "the cel's turn is not applied under the Move layer's slide")
    }

    // MARK: - Every tool's commit, asked where the canvas shows it

    /// A stroke made in canvas points and written through the inverse is shown exactly where it was
    /// made, at the width it was made — under a slide, a turn and a scale at once.
    func testAStrokeWrittenThroughTheInverseIsShownWhereItWasDrawn() throws {
        let move = CGAffineTransform(translationX: 30, y: 10).rotated(by: 0.3).scaledBy(x: 1.5, y: 1.5)
        let fx = layerUnderMove(move)
        let pose = fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id)
        let drawn = VectorStroke(brush: BrushLibrary.roundHard,
                                 color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 12,
                                 opacity: 1, samples: StrokeSamples(points: [CGPoint(x: 40, y: 50),
                                                                             CGPoint(x: 120, y: 90)]))
        let stored = try XCTUnwrap(CanvasManager.inLayerSpace(.stroke(drawn), shownThrough: pose)?.stroke)
        XCTAssertNotEqual(stored.samples.positions, drawn.samples.positions, "nothing was pulled back")
        let onScreen = try XCTUnwrap(shown(.stroke(stored), in: fx.manager, layer: fx.ink).stroke)
        for (a, b) in zip(onScreen.samples.positions, drawn.samples.positions) {
            assertSame(a, b, "a stored point is not shown where the pen put it")
        }
        XCTAssertEqual(onScreen.size, drawn.size, accuracy: 1e-6, "the mark is not shown at the size drawn")
    }

    /// **The smart shape, committed a frame change later**: the outline is in canvas points and is
    /// written through the pose it was drawn under.
    func testASmartShapeUnderAMoveLayerLandsWhereItsOutlineWas() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: -50, y: 20))
        let start = CGPoint(x: 60, y: 120), end = CGPoint(x: 200, y: 120)
        let samples = (0...10).map { i -> VectorSample in
            let t = CGFloat(i) / 10
            return VectorSample(x: start.x + (end.x - start.x) * t, y: start.y, pressure: 1)
        }
        fx.manager.beginInteractiveShape(ShapeGeometry(kind: .line, startPoint: start, endPoint: end),
                                         samples: samples)
        fx.manager.endInteractiveShape()
        fx.manager.commitInteractiveShape()
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.last?.stroke,
                                   "the shape committed nothing")
        let onScreen = try XCTUnwrap(shown(.stroke(stored), in: fx.manager, layer: fx.ink).stroke)
        let ys = onScreen.samples.positions.map(\.y)
        XCTAssertEqual(ys.min() ?? 0, 120, accuracy: 0.5, "the line is not shown on the row it was drawn on")
        XCTAssertEqual(ys.max() ?? 0, 120, accuracy: 0.5)
        XCTAssertEqual(onScreen.samples.positions.map(\.x).min() ?? 0, 60, accuracy: 1.5,
                       "the line is not shown starting where it was drawn")
    }

    /// **Text placed by a tap** is edited where the artist sees it and stored through the inverse, so
    /// its box is shown at the tap.
    func testTextPlacedUnderAMoveLayerIsShownAtTheTap() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 35, y: 15))
        fx.manager.selectedTool = .text
        let tap = CGPoint(x: 90, y: 70)
        fx.manager.beginTextSession(at: tap)
        fx.manager.updateTextString("Hi")
        fx.manager.commitInteractiveText()
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.compactMap(\.text).first,
                                   "the session committed no text")
        let onScreen = try XCTUnwrap(shown(.text(stored), in: fx.manager, layer: fx.ink).text)
        assertSame(onScreen.frame.corners.first, tap, "the box is not shown at the tap")
    }

    private func groupedTextFixture() throws -> (manager: CanvasManager, vector: VectorCanvas,
                 original: VectorTextElement, shownCorners: [CGPoint],
                 shownThrough: CGAffineTransform) {
        let container = CGAffineTransform(translationX: -8, y: 12)
        let fx = layerUnderMove(container)
        let group = AnimationGroup(displayName: "Label", tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        fx.manager.animationGroups = [group]
        let groupMap = CGAffineTransform(scaleX: 2, y: 0.5)
            .concatenating(CGAffineTransform(rotationAngle: 0.3))
            .concatenating(CGAffineTransform(translationX: 75, y: 25))
        let celMap = CGAffineTransform(translationX: 9, y: -4)
        var recipe = TextRecipe(string: "Hi")
        recipe.typography = Typography(pointSize: 24, tracking: 3, lineSpacing: 4, paragraphSpacing: 6)
        let original = VectorTextElement(recipe: recipe,
            frame: TextFrame(origin: CGPoint(x: 20, y: 30), size: CGSize(width: 58, height: 44), autoSize: false),
            motionGroupID: UUID(), animationGroupID: group.id)
        let vector = VectorCanvas(size: Self.size, elements: [.text(original)])
        fx.manager.layers[0].cels[0].vector = vector
        fx.manager.layers[0].cels[0].transformTracks = [
            TransformChannelID.group(group.id).id: CanvasFixture.poseTrack([(0, PoseQuad(box: Self.box, mappedBy: groupMap))]),
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(box: Self.box, mappedBy: celMap))])
        ]
        fx.manager.history.removeAll()
        let corners = original.frame.corners.map {
            $0.applying(groupMap).applying(celMap).applying(container)
        }
        return (fx.manager, vector, original, corners,
                groupMap.concatenating(celMap).concatenating(container))
    }

    func testGroupedTextHitAndEditorUseTheCompleteDrawnQuad() throws {
        let fx = try groupedTextFixture()
        let manager = fx.manager
        let image = try XCTUnwrap(manager.posedCelContent(for: manager.layers[0].cels[0], atFrame: 0,
            inheriting: manager.containerPose(ofLayerAt: 0, atFrame: 0))?.render(.full))
        let ink = try XCTUnwrap(PixelOps.opaqueContentBounds(image), "PREMISE: the posed text draws real letters")
        let expectedBox = try XCTUnwrap(Quad(fx.shownCorners)).boundingBox
        XCTAssertTrue(expectedBox.insetBy(dx: -2, dy: -2).contains(ink), "drawn ink lies in the actual posed quad")
        XCTAssertGreaterThan(ink.minX, fx.original.frame.boundingBox.maxX,
                             "PREMISE: the drawn label is clear of its stored box")
        let tap = CGPoint(x: fx.shownCorners.map(\.x).reduce(0, +) / 4,
                          y: fx.shownCorners.map(\.y).reduce(0, +) / 4)
        manager.selectedTool = .text
        manager.beginTextSession(at: tap)
        XCTAssertEqual(manager.textEditingElementID, fx.original.id, "the text tool reopens the shown label")
        for (actual, expected) in zip(manager.textFrame.corners, fx.shownCorners) {
            assertSame(actual, expected, "the editor follows group, cel, then container pose")
        }
        XCTAssertNotEqual(manager.textFrame.corners,
                          TextFrame.uprightCorners(origin: expectedBox.origin, size: expectedBox.size),
                          "the rotated/nonuniform quad must not become its axis-aligned bounds")
        manager.cancelInteractiveText()
        XCTAssertEqual(fx.vector.elements.compactMap(\.text), [fx.original])
        XCTAssertNil(fx.vector.editingElementID)
        XCTAssertFalse(manager.history.canUndo)
    }

    func testMovingAndDistortingTheGroupedTextEditorPullsBackItsWholeEditedQuad() throws {
        let fx = try groupedTextFixture()
        let manager = fx.manager
        XCTAssertTrue(manager.beginEditingText(elementID: fx.original.id))
        var expectedShown = fx.shownCorners.map { CGPoint(x: $0.x + 15, y: $0.y - 8) }
        manager.beginTextFrameDrag()
        manager.dragTextFrame(toOrigin: expectedShown[0])
        manager.endTextFrameDrag()
        expectedShown[2] = CGPoint(x: expectedShown[2].x + 8, y: expectedShown[2].y + 5)
        manager.textCornerMode = .distort
        manager.beginTextHandleDrag(.bottomRight)
        manager.dragTextHandle(to: expectedShown[2])
        manager.endTextHandleDrag()
        for (actual, expected) in zip(manager.textFrame.corners, expectedShown) {
            assertSame(actual, expected, "the existing move band and corner grip authored this quad")
        }
        XCTAssertTrue(manager.commitInteractiveText())
        let stored = try XCTUnwrap(fx.vector.elements.first?.text)
        for (actual, expected) in zip(stored.frame.corners, expectedShown.map({ $0.applying(fx.shownThrough.inverted()) })) {
            assertSame(actual, expected, "landing undoes container, cel and group in reverse order")
        }
        XCTAssertEqual(stored.motionGroupID, fx.original.motionGroupID)
        XCTAssertEqual(stored.animationGroupID, fx.original.animationGroupID)
        let posed = try XCTUnwrap(manager.celPoseMaps(fx.vector.elements, layerID: manager.layers[0].id,
            celID: manager.layers[0].cels[0].id, atFrame: 0)[stored.id])
        let shown = try XCTUnwrap(VectorCanvas.mapping(.text(stored), through: posed)?.text)
        for (actual, expected) in zip(shown.frame.corners, expectedShown) {
            assertSame(actual, expected, "the committed drawing round-trips to the edited quad")
        }
        let image = try XCTUnwrap(manager.posedCelContent(for: manager.layers[0].cels[0], atFrame: 0,
            inheriting: manager.containerPose(ofLayerAt: 0, atFrame: 0))?.render(.full))
        let ink = try XCTUnwrap(PixelOps.opaqueContentBounds(image), "the committed distorted text is really drawn")
        XCTAssertTrue(try XCTUnwrap(Quad(expectedShown)).boundingBox.insetBy(dx: -2, dy: -2).contains(ink))
        manager.undo()
        XCTAssertEqual(fx.vector.elements.compactMap(\.text), [fx.original])
        XCTAssertFalse(manager.history.canUndo)
    }

    func testGroupedTextNoOpEditUndoRedoAndCurrentPackageKeepIdentityAndPose() throws {
        let fx = try groupedTextFixture()
        let manager = fx.manager
        XCTAssertTrue(manager.beginEditingText(elementID: fx.original.id))
        XCTAssertTrue(manager.commitInteractiveText())
        XCTAssertEqual(fx.vector.elements.compactMap(\.text), [fx.original], "a no-op is the exact original, without inverse-rounding drift")
        XCTAssertNil(fx.vector.editingElementID, "a no-op still clears the original's suppression")
        XCTAssertFalse(manager.history.canUndo, "opening and closing a label creates no history step")
        XCTAssertTrue(manager.beginEditingText(elementID: fx.original.id))
        manager.updateTextString("Ho")
        XCTAssertTrue(manager.commitInteractiveText())
        let edited = try XCTUnwrap(fx.vector.elements.first?.text)
        XCTAssertEqual(edited.id, fx.original.id)
        XCTAssertEqual(edited.motionGroupID, fx.original.motionGroupID)
        XCTAssertEqual(edited.animationGroupID, fx.original.animationGroupID)
        XCTAssertEqual(edited.recipe.string, "Ho")
        for (actual, expected) in zip(edited.frame.corners, fx.original.frame.corners) {
            assertSame(actual, expected, "editing words pulls the full quad back, not its bounds")
        }
        XCTAssertTrue(manager.history.canUndo)
        manager.undo()
        XCTAssertEqual(fx.vector.elements.compactMap(\.text), [fx.original])
        XCTAssertFalse(manager.history.canUndo, "one text edit is one step")
        manager.redo()
        XCTAssertEqual(fx.vector.elements.first?.text, edited)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grouped-text-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("label.paintproj", isDirectory: true)
        let saved = expectation(description: "current grouped-text package saved")
        ProjectStore.save(manager, to: url) { savedURL in
            XCTAssertEqual(savedURL, url, "the current writer completed the isolated package")
            saved.fulfill()
        }
        wait(for: [saved], timeout: 30)
        let loaded = try XCTUnwrap(ProjectStore.load(from: url))
        let reloaded = try XCTUnwrap(loaded.layers[0].cels[0].vector?.elements.first?.text)
        XCTAssertEqual(reloaded, edited)
        XCTAssertEqual(loaded.animationGroups, manager.animationGroups)
        XCTAssertEqual(loaded.layers[0].cels[0].transformTracks, manager.layers[0].cels[0].transformTracks)
        let before = try XCTUnwrap(manager.posedCelContent(for: manager.layers[0].cels[0], atFrame: 0,
            inheriting: manager.containerPose(ofLayerAt: 0, atFrame: 0))?.render(.full)?.cgImage)
        let after = try XCTUnwrap(loaded.posedCelContent(for: loaded.layers[0].cels[0], atFrame: 0,
            inheriting: loaded.containerPose(ofLayerAt: 0, atFrame: 0))?.render(.full)?.cgImage)
        let pixels = try XCTUnwrap(CanvasFixture.rgbaBytes(before))
        XCTAssertTrue(pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 })
        XCTAssertEqual(pixels, CanvasFixture.rgbaBytes(after), "the edited label stays drawn in the same group pose after a current save/load")
    }

    func testAnAutoSizedTextNoOpKeepsItsExactFrameAndTheLastFocusedDraftStillLands() throws {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addVectorLayer()
        manager.beginTextSession(at: CGPoint(x: 20, y: 30))
        manager.textRecipe.typography = Typography(pointSize: 24, tracking: 3, lineSpacing: 4, paragraphSpacing: 6)
        manager.updateTextString("Hi")
        XCTAssertTrue(manager.commitInteractiveText())
        let vector = try XCTUnwrap(manager.layers[0].cels[0].vector)
        let original = try XCTUnwrap(vector.elements.first?.text)
        XCTAssertTrue(original.frame.autoSize, "PREMISE: this is current authored point text")
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
        XCTAssertTrue(before.enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 },
                      "PREMISE: the original label has real drawn letters")
        manager.history.removeAll()

        XCTAssertTrue(manager.beginEditingText(elementID: original.id))
        XCTAssertTrue(manager.commitInteractiveText())
        XCTAssertEqual(vector.elements.first?.text, original,
                       "an untouched auto-sized label retains exact corners, mode, sizing bit and typography")
        XCTAssertNil(vector.editingElementID, "the unchanged label returns through the existing suppression owner")
        XCTAssertFalse(manager.history.canUndo, "opening and closing auto-sized text creates no edit")
        XCTAssertEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)), before,
                       "the unchanged auto-sized label draws exactly the same picture")

        XCTAssertTrue(manager.beginEditingText(elementID: original.id))
        manager.textIsFocused = true
        manager.textDraftReader = { "Hi there" }
        XCTAssertTrue(manager.commitInteractiveText())
        let edited = try XCTUnwrap(vector.elements.first?.text)
        XCTAssertEqual(edited.recipe.string, "Hi there", "the final focused draft is read before deciding whether anything changed")
        XCTAssertEqual(edited.recipe.typography, original.recipe.typography)
        let expectedSize = TextLayout.autoSize(for: edited.recipe, font: TextLayout.resolvedFont(for: edited.recipe).font)
        XCTAssertEqual(edited.frame, original.frame.resized(to: expectedSize), "a real text edit still measures and grows the box")
        XCTAssertGreaterThan(edited.frame.size.width, original.frame.size.width)
        XCTAssertTrue(manager.history.canUndo, "the actual new words produce one text edit")
        XCTAssertNotEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)), before,
                          "the final focused words are really drawn")
        manager.undo()
        XCTAssertEqual(vector.elements.first?.text, original)
        XCTAssertFalse(manager.history.canUndo, "the real text change is one history step")
    }

    func testAnAutoSizedLabelScaledPastTheFontBoundDoesNotResizeWhenMerelyReopened() throws {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = CGSize(width: 1400, height: 1200)
        manager.addVectorLayer()
        manager.beginTextSession(at: CGPoint(x: 500, y: 300))
        manager.textRecipe.typography = Typography(pointSize: 400, tracking: 3, lineSpacing: 4, paragraphSpacing: 6)
        manager.updateTextString("Hi")
        XCTAssertTrue(manager.commitInteractiveText())
        let vector = try XCTUnwrap(manager.layers[0].cels[0].vector)
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        var transform = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        transform.scale *= 2
        manager.nudgeVectorFloat(to: transform)
        XCTAssertTrue(manager.commitVectorFloatIfNeeded())
        let original = try XCTUnwrap(vector.elements.first?.text)
        XCTAssertEqual(original.recipe.typography.pointSize, 800, "PREMISE: actual Move retains raw scaled typography")
        XCTAssertTrue(original.frame.autoSize, "PREMISE: scaling point text does not turn it into a hand-sized box")
        XCTAssertEqual(original.frame.mode, .affine)
        let recomputed = TextLayout.autoSize(for: original.recipe, font: TextLayout.resolvedFont(for: original.recipe).font)
        XCTAssertNotEqual(recomputed, original.frame.size, "PREMISE: remeasuring at the render font bound would change the authored box")
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
        XCTAssertTrue(before.enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 },
                      "PREMISE: the scaled label remains a real drawn picture")
        manager.history.removeAll()

        XCTAssertTrue(manager.beginEditingText(elementID: original.id))
        XCTAssertTrue(manager.commitInteractiveText())
        XCTAssertEqual(vector.elements.first?.text, original,
                       "merely reopening scaled point text preserves exact geometry, mode, auto-size and raw typography")
        XCTAssertNil(vector.editingElementID)
        XCTAssertFalse(manager.history.canUndo, "a render clamp is not an artist's text edit")
        XCTAssertEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)), before,
                       "closing unchanged scaled text preserves its drawn picture")

        // The staged public witness consumes this actual Move/current-writer output. An ordinary
        // logic pass proves the assertions above, but cannot qualify an export it did not request.
        guard let requested = ProcessInfo.processInfo.environment["PAINTAPP_TEXT_AUTOSIZE_STAGE_UUID"] else { return }
        let nonce = try XCTUnwrap(UUID(uuidString: requested), "PREMISE: a fresh writer-stage UUID").uuidString
        let files = FileManager.default
        let root = try XCTUnwrap(files.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("text-autosize-writer-\(nonce)", isDirectory: true)
        XCTAssertFalse(files.fileExists(atPath: root.path), "PREMISE: the retained writer fixture is fresh")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        let priorRoot = ProjectBackupManager.rootDirectoryOverride
        ProjectBackupManager.rootDirectoryOverride = root
        PackageRenameGate.resetForTesting()
        defer {
            ProjectBackupManager.rootDirectoryOverride = priorRoot
            PackageRenameGate.resetForTesting()
        }
        manager.projectName = "Auto Sized 800 \(nonce)"
        let package = root.appendingPathComponent("\(manager.projectName).paintproj", isDirectory: true)
        let saved = expectation(description: "current writer retains the actual scaled point text")
        var savedURL: URL?
        ProjectStore.save(manager, to: package) { savedURL = $0; saved.fulfill() }
        wait(for: [saved], timeout: 30)
        XCTAssertEqual(savedURL?.standardizedFileURL, package.standardizedFileURL)
        let loaded = try XCTUnwrap(ProjectStore.load(from: try XCTUnwrap(savedURL)))
        let reopened = try XCTUnwrap(loaded.layers[0].cels[0].vector)
        XCTAssertEqual(reopened.elements.first?.text, original,
                       "the current package retains the actual Move's raw800, auto-size frame and identity")
        XCTAssertEqual(CanvasFixture.rgbaBytes(try XCTUnwrap(reopened.render()?.cgImage)), before,
                       "the current package reopens the actual scaled label's picture")
    }

    func testAProjectivelyShownAutoSizedTextNoOpRestoresItsExactStoredModeAndTypography() throws {
        let fx = try groupedTextFixture()
        let manager = fx.manager
        var original = fx.original
        original.frame.autoSize = true
        fx.vector.upsertText(original)
        let groupID = try XCTUnwrap(original.animationGroupID)
        let groupMap = Homography(a: 1, b: 0, c: 25, d: 0, e: 1, f: 10, g: 0.002, h: 0, i: 1)
        let groupPose = try XCTUnwrap(PoseQuad(box: Self.box, mappedThrough: groupMap))
        manager.layers[0].cels[0].transformTracks[TransformChannelID.group(groupID).id] = CanvasFixture.poseTrack([(0, groupPose)])
        let inherited = manager.containerPose(ofLayerAt: 0, atFrame: 0)
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(manager.posedCelContent(
            for: manager.layers[0].cels[0], atFrame: 0, inheriting: inherited)?.render(.full)?.cgImage)))
        XCTAssertTrue(before.enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 },
                      "PREMISE: the fully posed projective label draws real letters")
        manager.history.removeAll()

        XCTAssertTrue(manager.beginEditingText(elementID: original.id))
        XCTAssertEqual(manager.textFrame.mode, .projective, "PREMISE: the shown draft uses the complete projective pose")
        XCTAssertFalse(manager.textFrame.autoSize, "PREMISE: the projective display mapping changes the draft's sizing bit")
        for (actual, stored) in zip(manager.textFrame.corners, original.frame.corners) {
            let grouped = try XCTUnwrap(groupMap.map(stored))
            let expected = grouped.applying(CGAffineTransform(translationX: 9, y: -4))
                .applying(CGAffineTransform(translationX: -8, y: 12))
            assertSame(actual, expected, "projective group, cel and container pose compose in render order")
        }
        XCTAssertTrue(manager.commitInteractiveText())
        XCTAssertEqual(fx.vector.elements.first?.text, original,
                       "a display-only projective mode and sizing bit never replace the untouched stored original")
        XCTAssertEqual(fx.vector.elements.first?.text?.frame.mode, .affine)
        XCTAssertEqual(fx.vector.elements.first?.text?.frame.autoSize, true)
        XCTAssertEqual(fx.vector.elements.first?.text?.recipe.typography, original.recipe.typography)
        XCTAssertNil(fx.vector.editingElementID)
        XCTAssertFalse(manager.history.canUndo)
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(manager.posedCelContent(
            for: manager.layers[0].cels[0], atFrame: 0, inheriting: inherited)?.render(.full)?.cgImage)))
        XCTAssertEqual(after, before, "an unchanged projectively posed label retains the complete drawn picture")
    }

    func testAProjectivelyPosedTextEditRefusesAnUnmappableQuadWithoutReplacingTheOriginal() throws {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addVectorLayer()
        let group = AnimationGroup(displayName: "Perspective", tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups = [group]
        let vector = try XCTUnwrap(manager.layers[0].cels[0].vector)
        let original = VectorTextElement(recipe: TextRecipe(string: "Hi"),
            frame: TextFrame(origin: CGPoint(x: 20, y: 30), size: CGSize(width: 70, height: 60), autoSize: false),
            motionGroupID: UUID(), animationGroupID: group.id)
        vector.upsertText(original)
        let map = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: 0.005, h: 0, i: 1)
        let pose = try XCTUnwrap(PoseQuad(box: Self.box, mappedThrough: map))
        manager.layers[0].cels[0].transformTracks[TransformChannelID.group(group.id).id] = CanvasFixture.poseTrack([(0, pose)])
        manager.history.removeAll()
        XCTAssertTrue(manager.beginEditingText(elementID: original.id))
        let shown = try XCTUnwrap(VectorCanvas.mapping(.text(original), through: PoseMap(map))?.text)
        for (actual, expected) in zip(manager.textFrame.corners, shown.frame.corners) {
            assertSame(actual, expected, "the projective overlay is the drawn quad")
        }
        // A normal translation of the editor box can reach the inverse's vanishing line. The box
        // itself is valid on screen; it has no storable pre-image. Refuse rather than save bounds.
        let shift = 200 - manager.textFrame.corners[0].x
        manager.textFrame.corners = manager.textFrame.corners.map { CGPoint(x: $0.x + shift, y: $0.y) }
        XCTAssertNotNil(manager.textFrame.homography, "PREMISE: this is a valid edited screen quad")
        XCTAssertFalse(manager.commitInteractiveText())
        XCTAssertTrue(manager.textGestureActive, "a refusal keeps the editable draft")
        XCTAssertEqual(vector.elements.compactMap(\.text), [original])
        XCTAssertFalse(manager.history.canUndo)
        manager.cancelInteractiveText()
        XCTAssertNil(vector.editingElementID)
        XCTAssertEqual(vector.elements.compactMap(\.text), [original])
    }

    private func repeatedTextFixture(sourceOnly: Bool) throws -> (manager: CanvasManager, vector: VectorCanvas,
                                                                 original: VectorTextElement, shownCorners: [CGPoint]) {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addVectorLayer(name: "Repeated text")
        manager.addTransformLayer(name: "Repeat")
        manager.addTransformLayer(name: "Outer Move")
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: sourceOnly ? 3 : 24)])
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 24)])
        CanvasFixture.setCelLayout(manager, layerIndex: 2, [(start: 0, length: 24)])
        manager.layers[1].transform = LayerPose(pose: PoseQuad(restingIn: Self.box), mode: .repeat, repeatPeriod: 12)
        func groupMap(_ frame: Int) -> CGAffineTransform {
            CGAffineTransform(scaleX: 1.5, y: 0.8).concatenating(CGAffineTransform(translationX: CGFloat(frame * 6), y: 0))
        }
        func celMap(_ frame: Int) -> CGAffineTransform {
            CGAffineTransform(rotationAngle: 0.12).concatenating(CGAffineTransform(translationX: 0, y: CGFloat(frame * 2)))
        }
        func outerMap(_ frame: Int) -> CGAffineTransform {
            CGAffineTransform(rotationAngle: -0.08)
                .concatenating(CGAffineTransform(translationX: CGFloat(frame * 2), y: CGFloat(frame)))
        }
        manager.layers[2].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: outerMap(0)),
            track: CanvasFixture.poseTrack([(0, PoseQuad(box: Self.box, mappedBy: outerMap(0))),
                                            (23, PoseQuad(box: Self.box, mappedBy: outerMap(23)))], interpolation: .linear))
        let group = AnimationGroup(displayName: "Looped label", tagColor: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.animationGroups = [group]
        var recipe = TextRecipe(string: "Hi")
        recipe.typography = Typography(pointSize: 24, tracking: 3, lineSpacing: 4, paragraphSpacing: 6)
        let original = VectorTextElement(recipe: recipe,
            frame: TextFrame(origin: CGPoint(x: 20, y: 30), size: CGSize(width: 58, height: 44), autoSize: false),
            motionGroupID: UUID(), animationGroupID: group.id)
        let vector = VectorCanvas(size: Self.size, elements: [.text(original)])
        manager.layers[0].cels[0].vector = vector
        let last = sourceOnly ? 2 : 23
        manager.layers[0].cels[0].transformTracks = [
            TransformChannelID.group(group.id).id: CanvasFixture.poseTrack(
                [(0, PoseQuad(box: Self.box, mappedBy: groupMap(0))),
                 (last, PoseQuad(box: Self.box, mappedBy: groupMap(last)))], interpolation: .linear),
            TransformChannelID.cel.id: CanvasFixture.poseTrack(
                [(0, PoseQuad(box: Self.box, mappedBy: celMap(0))),
                 (last, PoseQuad(box: Self.box, mappedBy: celMap(last)))], interpolation: .linear)
        ]
        manager.currentLayerIndex = 0
        manager.currentFrame = 14
        manager.history.removeAll()
        // Repeat resolves the cel/group at 2; the poser above Repeat still resolves at 14.
        let corners = original.frame.corners.map {
            $0.applying(groupMap(2)).applying(celMap(2)).applying(outerMap(14))
        }
        return (manager, vector, original, corners)
    }

    private func repeatedTextFrame(_ manager: CanvasManager) throws -> CGImage {
        let request = try XCTUnwrap(manager.makeRenderRequest(atFrame: manager.currentFrame, includeBackground: false))
        return try XCTUnwrap(Compositor.composite(request), "the actual repeated document must draw")
    }

    func testARepeatedHeldTextTapUsesSourceChannelsAndDocumentTimeContainerForAnExactNoOp() throws {
        let fx = try repeatedTextFixture(sourceOnly: false)
        let manager = fx.manager
        XCTAssertEqual(manager.displayedFrame(forLayer: 0, atFrame: 14), 2, "PREMISE: the shown source differs from the playhead")
        XCTAssertEqual(manager.activeCelIndex(inLayer: 0, atFrame: 14), 0, "PREMISE: one held cel covers both frames")
        let beforeImage = try repeatedTextFrame(manager)
        let before = try XCTUnwrap(CanvasFixture.rgbaBytes(beforeImage))
        let ink = try XCTUnwrap(PixelOps.opaqueContentBounds(UIImage(cgImage: beforeImage)), "PREMISE: actual repeated letters are drawn")
        let expectedBox = try XCTUnwrap(Quad(fx.shownCorners)).boundingBox
        XCTAssertTrue(expectedBox.insetBy(dx: -2, dy: -2).contains(ink), "PREMISE: actual pixels follow source channels and the document-time outer pose")
        let tap = CGPoint(x: fx.shownCorners.map(\.x).reduce(0, +) / 4,
                          y: fx.shownCorners.map(\.y).reduce(0, +) / 4)

        manager.beginTextSession(at: tap)
        XCTAssertEqual(manager.textEditingElementID, fx.original.id, "Text reopens the label where Repeat actually draws it")
        XCTAssertEqual(manager.textGestureCelID, manager.layers[0].cels[0].id)
        let overlayError = zip(manager.textFrame.corners, fx.shownCorners)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? .infinity
        XCTAssertLessThan(overlayError, 1e-6, "the actual overlay uses source channels and keeps outer container time")
        XCTAssertTrue(manager.commitInteractiveText())
        XCTAssertEqual(fx.vector.elements.first?.text, fx.original, "the repeated label's no-op keeps exact identity, frame, groups and typography")
        XCTAssertNil(fx.vector.editingElementID)
        XCTAssertFalse(manager.history.canUndo)
        XCTAssertEqual(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)), before,
                       "closing the unchanged repeated label preserves its actual document picture")
    }

    func testEditingRepeatedTextByIDUsesShownCelsAndRetainsTheirAnimationThroughHistory() throws {
        for sourceOnly in [false, true] {
            let fx = try repeatedTextFixture(sourceOnly: sourceOnly)
            let manager = fx.manager
            if sourceOnly {
                XCTAssertNil(manager.activeCelIndex(inLayer: 0, atFrame: 14), "PREMISE: no drawing exists at the raw playhead")
            } else {
                XCTAssertEqual(manager.activeCelIndex(inLayer: 0, atFrame: 14), 0, "PREMISE: one held cel covers source and playhead")
            }
            XCTAssertEqual(manager.displayedCelIndex(inLayer: 0, atFrame: 14), 0, "PREMISE: Repeat shows the earlier drawing")
            let before = try XCTUnwrap(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)))
            XCTAssertTrue(before.enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 }, "PREMISE: real repeated text is visible")
            let opened = manager.beginEditingText(elementID: fx.original.id)
            XCTAssertTrue(opened, "Edit Text must open the shown source cel even when the playhead holds none")
            guard opened else { return }
            XCTAssertEqual(manager.textGestureCelID, manager.layers[0].cels[0].id)
            let overlayError = zip(manager.textFrame.corners, fx.shownCorners)
                .map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? .infinity
            XCTAssertLessThan(overlayError, 1e-6, "ID Edit's actual overlay follows source channels and document-time outer pose")
            manager.updateTextString("Ho")
            XCTAssertTrue(manager.commitInteractiveText())
            var expected = fx.original
            expected.recipe.string = "Ho"
            let edited = try XCTUnwrap(fx.vector.elements.first?.text)
            XCTAssertEqual(edited.id, expected.id)
            XCTAssertEqual(edited.motionGroupID, expected.motionGroupID)
            XCTAssertEqual(edited.animationGroupID, expected.animationGroupID)
            XCTAssertEqual(edited.recipe.string, expected.recipe.string)
            XCTAssertEqual(edited.recipe.font, expected.recipe.font)
            XCTAssertEqual(edited.recipe.color, expected.recipe.color)
            XCTAssertEqual(edited.recipe.opacity, expected.recipe.opacity)
            XCTAssertEqual(edited.recipe.typography.pointSize, expected.recipe.typography.pointSize, accuracy: 1e-6)
            XCTAssertEqual(edited.recipe.typography.tracking, expected.recipe.typography.tracking, accuracy: 1e-6)
            XCTAssertEqual(edited.recipe.typography.lineSpacing, expected.recipe.typography.lineSpacing, accuracy: 1e-6)
            XCTAssertEqual(edited.recipe.typography.paragraphSpacing, expected.recipe.typography.paragraphSpacing, accuracy: 1e-6)
            XCTAssertEqual(edited.recipe.typography.lineHeightMultiple, expected.recipe.typography.lineHeightMultiple)
            XCTAssertEqual(edited.recipe.typography.alignment, expected.recipe.typography.alignment)
            for (actual, original) in zip(edited.frame.corners, expected.frame.corners) {
                assertSame(actual, original, "the real edit pulls back into the source cel's original full quad")
            }
            XCTAssertEqual(manager.layers[0].cels.count, 1, "editing a repeated source does not create a playhead drawing")
            let after = try XCTUnwrap(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)))
            XCTAssertNotEqual(after, before, "the actual repeated picture contains the changed letters")
            XCTAssertTrue(manager.history.canUndo)
            manager.undo()
            XCTAssertEqual(fx.vector.elements.first?.text, fx.original)
            XCTAssertFalse(manager.history.canUndo, "one text edit is one history step")
            XCTAssertEqual(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)), before)
            manager.redo()
            XCTAssertEqual(fx.vector.elements.first?.text, edited)
            XCTAssertEqual(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)), after)
        }
    }

    func testNewTextOnARepeatedSourceOnlyCelLandsWhereItWasDrawnAndUndoesAsOneEdit() throws {
        let fx = try repeatedTextFixture(sourceOnly: true)
        let manager = fx.manager
        fx.vector.elements = []
        let sourceCelID = manager.layers[0].cels[0].id
        let point = CGPoint(x: 100, y: 90)
        manager.beginTextSession(at: point)
        XCTAssertTrue(manager.textGestureActive, "a new text box can open on the drawing Repeat shows")
        guard manager.textGestureActive else { return }
        XCTAssertEqual(manager.textGestureCelID, sourceCelID)
        manager.textRecipe.typography.pointSize = 24
        manager.updateTextString("Hi")
        let expectedBox = manager.textFrame.boundingBox
        XCTAssertEqual(manager.textFrame.corners[0], point)
        XCTAssertTrue(manager.commitInteractiveText())
        let text = try XCTUnwrap(fx.vector.elements.first?.text)
        XCTAssertNil(text.animationGroupID, "new text joins the shown cel, not an existing element's group")
        XCTAssertNil(text.motionGroupID)
        XCTAssertEqual(manager.layers[0].cels.count, 1)
        XCTAssertEqual(manager.layers[0].cels[0].id, sourceCelID)
        XCTAssertNil(manager.activeCelIndex(inLayer: 0, atFrame: 14))
        let afterImage = try repeatedTextFrame(manager)
        let ink = try XCTUnwrap(PixelOps.opaqueContentBounds(UIImage(cgImage: afterImage)), "the new repeated label is actually drawn")
        XCTAssertTrue(expectedBox.insetBy(dx: -2, dy: -2).contains(ink),
                      "new text removes the source cel pose and document-time outer pose before landing")
        let after = try XCTUnwrap(CanvasFixture.rgbaBytes(afterImage))
        XCTAssertTrue(manager.history.canUndo)
        manager.undo()
        XCTAssertTrue(fx.vector.elements.isEmpty)
        XCTAssertFalse(manager.history.canUndo)
        let empty = try XCTUnwrap(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)))
        XCTAssertFalse(empty.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 }, "Undo removes the actual shown new label")
        manager.redo()
        XCTAssertEqual(fx.vector.elements.first?.text, text)
        XCTAssertEqual(CanvasFixture.rgbaBytes(try repeatedTextFrame(manager)), after)
    }

    /// **A loop drawn round the ink where it is shown** catches it: the container pose reaches the
    /// per-element pull-back the lasso, the Move box and every nudge all read.
    func testALassoRoundTheShownInkPullsBackOntoTheStoredInk() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 80, y: 0))
        let vector = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector)
        vector.addStroke(VectorStroke(brush: BrushLibrary.roundHard,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 6,
                                      opacity: 1, samples: StrokeSamples(points: [CGPoint(x: 40, y: 40),
                                                                                  CGPoint(x: 60, y: 40)])))
        let element = try XCTUnwrap(vector.elements.last)
        let shownLoop = CGPath(rect: CGRect(x: 110, y: 30, width: 40, height: 20), transform: nil)
        let maps = fx.manager.celPoseMaps(vector.elements, layerID: fx.manager.layers[fx.ink].id,
                                          celID: fx.manager.layers[fx.ink].cels[0].id, atFrame: 0)
        let loops = CanvasManager.lassoLoops(shownLoop, posedBy: maps)
        XCTAssertTrue(loops.path(for: element.id).contains(CGPoint(x: 50, y: 40)),
                      "the loop round the shown ink does not reach the ink where it is stored")
    }

    /// **The universal eraser** reaches every layer at once, so its gesture is in canvas points and
    /// each target takes it through its own pose.
    func testAUniversalEraserReachesEachLayerThroughItsOwnPose() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 25, y: 0))
        let target = try XCTUnwrap(fx.manager.universalEraseTargets().first)
        XCTAssertEqual(target.pose, fx.manager.inkPose(forLayerID: fx.manager.layers[fx.ink].id))
        let own = try XCTUnwrap(target.inOwnSpace(StrokeSamples(points: [CGPoint(x: 75, y: 9)]), size: 8))
        assertSame(own.run.positions.first, CGPoint(x: 50, y: 9), "the eraser is not taken into the layer")
        XCTAssertEqual(own.size, 8, accuracy: 1e-9)
    }

    /// **A fill tapped on the shown picture floods the region the tap is shown in.** A hollow box at
    /// rest, slid 100 points right by a Move layer: the tap inside the box *as shown* is outside it
    /// at rest, so without the pull-back the flood takes the paper around the box instead.
    func testAFillTappedInsideTheShownBoxFillsTheBox() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box,
                                                               mappedBy: CGAffineTransform(translationX: 100, y: 0)),
                                                mode: .move)
        manager.currentLayerIndex = 0
        manager.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        let ring = UIGraphicsImageRenderer(size: Self.size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setStroke()
            ctx.cgContext.setLineWidth(4)
            ctx.cgContext.stroke(CGRect(x: 30, y: 30, width: 60, height: 60))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ring)

        manager.beginInteractiveFill(at: CGPoint(x: 160, y: 60))
        manager.endInteractiveFill()
        manager.waitForFillWork()
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { done.fulfill() }
        wait(for: [done], timeout: 6)
        manager.commitInteractiveFill()

        let cg = try XCTUnwrap(try manager.layers[0].cels[0].raster.renderToUIImage().get().cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        func red(_ x: Int, _ y: Int) -> Bool {
            let i = (y * cg.width + x) * 4
            return bytes[i + 3] > 200 && bytes[i] > 200 && bytes[i + 1] < 60
        }
        XCTAssertTrue(red(60, 60), "the box the tap is shown in was not filled")
        XCTAssertFalse(red(160, 60), "the paper beside the box was filled instead")
    }

    // MARK: - Pixels: a raster lasso and its Move, asked where the canvas shows them

    /// **A pixel layer holding a 40-point black square at (20, 100), under a Move layer that slides it
    /// 80 points right** — so the artist sees it at (100, 100), and a loop drawn round it there is
    /// round pixels that are stored 80 points to the left of the loop. A bystander square at (100, 20)
    /// is shown at (180, 20), outside any loop drawn round the first.
    private func pixelsUnderMove() -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box,
                                                               mappedBy: CGAffineTransform(translationX: 80, y: 0)),
                                                mode: .move)
        manager.currentLayerIndex = 0
        let ink = UIGraphicsImageRenderer(size: Self.size, format: PixelOps.transparentFormat()).image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 20, y: 100, width: 40, height: 40))
            context.cgContext.fill(CGRect(x: 100, y: 20, width: 30, height: 30))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        return manager
    }

    /// A loop round the square **as the artist sees it**, on the layer's current cel.
    private func selectShownSquare(_ manager: CanvasManager) {
        let loop = CGRect(x: 90, y: 90, width: 60, height: 60)
        manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop)
    }

    /// Whether a pixel of a layer's *stored* picture is inked.
    private func storedInk(_ manager: CanvasManager, layer: Int = 0, _ x: Int, _ y: Int) throws -> Bool {
        let image = (try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[layer].cels[0], canvasSize: Self.size)))
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return false }
        return bytes[(y * cg.width + x) * 4 + 3] > 200
    }

    private func nudgeFloat(_ manager: CanvasManager, dx: CGFloat) throws {
        var transform = try XCTUnwrap(manager.floatingPiece?.transform, "nothing floats")
        transform.position.x += dx
        manager.updateFloatingPose(transform: transform, distortQuad: nil)
    }

    /// **The raster Move lifts what the loop is round and puts it down where it is dropped.** Lifted
    /// from the stored pixels the loop catches nothing (the ink is 80 points to its left), and set
    /// down by writing the piece's canvas position into the layer it lands 80 points from where it was
    /// let go — both halves of that are what the pose-aware lift and landing exist to prevent.
    func testARasterMoveUnderAMoveLayerLiftsWhatIsShownAndLandsWhereItIsDropped() throws {
        let manager = pixelsUnderMove()
        selectShownSquare(manager)

        manager.beginMove()
        let piece = try XCTUnwrap(manager.floatingPiece, "Move lifted nothing")
        XCTAssertNotNil(PixelOps.opaqueContentBounds(piece.pieceImage),
                        "the loop is round the shown ink and the piece it lifted is empty")
        let hole = try XCTUnwrap(piece.remainderPreview)
        XCTAssertEqual(PixelOps.opaqueContentBounds(try hole.resolveImage().get()), CGRect(x: 100, y: 20, width: 30, height: 30),
                       "the hole is not the lifted ink and nothing else: the cel should keep only the bystander, where it is stored")

        try nudgeFloat(manager, dx: 30)
        manager.commitFloatingPieceIfNeeded()

        XCTAssertFalse(try storedInk(manager, 30, 120), "the square is still where it was stored")
        XCTAssertTrue(try storedInk(manager, 70, 120),
                      "dropped 30 points right of where it was shown, the square is not stored 30 right of where it was")
        XCTAssertFalse(try storedInk(manager, 150, 120), "the drop was written at the pen's own coordinates, a pose away")
        XCTAssertTrue(try storedInk(manager, 110, 30), "what the loop was not round moved: it is no longer stored where it was")
        XCTAssertFalse(try storedInk(manager, 190, 30), "what the loop was not round was carried a pose along with the cel's remainder")
    }

    /// **Duplicate copies what the loop is round onto a new layer, and the new layer is shown under
    /// the same Move layer** — so a copy let go in place is shown exactly over the original.
    func testADuplicateUnderAMoveLayerLandsOverTheOriginal() throws {
        let manager = pixelsUnderMove()
        selectShownSquare(manager)

        manager.beginDuplicate()
        XCTAssertEqual(manager.layers.count, 3, "the copy's layer was not added")
        manager.commitFloatingPieceIfNeeded()

        let copy = try XCTUnwrap(manager.layers.firstIndex { $0.id != manager.layers[0].id && $0.kind == .raster })
        XCTAssertTrue(try storedInk(manager, layer: copy, 30, 120), "the copy is not stored where the original is")
        XCTAssertFalse(try storedInk(manager, layer: copy, 110, 120), "the copy was written at the pen's own coordinates")
        XCTAssertTrue(try storedInk(manager, layer: 0, 30, 120), "a copy took the original with it")
    }

    /// **To New Layer cuts in the layer's own space**: the piece leaves the source and arrives where it
    /// was stored, and so is shown where it was.
    func testToNewLayerUnderAMoveLayerCutsWhatTheLoopIsRoundAndNothingElse() throws {
        let manager = pixelsUnderMove()
        selectShownSquare(manager)

        manager.moveSelectionToNewLayer()

        let source = try XCTUnwrap(manager.layers.firstIndex { $0.name == "ink" })
        let moved = try XCTUnwrap(manager.layers.firstIndex { $0.kind == .raster && $0.name != "ink" })
        XCTAssertFalse(try storedInk(manager, layer: source, 30, 120), "the source kept what the loop is round")
        XCTAssertTrue(try storedInk(manager, layer: moved, 30, 120), "the new layer did not get it")
    }

    /// **Clear and Fill reach the stored pixels through the loop pulled back**, not through the loop as
    /// drawn, which is 80 points from them.
    func testClearAndFillOnARasterSelectionUnderAMoveLayerActWhereTheLoopIsShown() throws {
        let cleared = pixelsUnderMove()
        selectShownSquare(cleared)
        cleared.clearSelectionPixels()
        XCTAssertFalse(try storedInk(cleared, 30, 120), "Clear missed the ink the loop is round")

        let filled = pixelsUnderMove()
        filled.brushColor = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
        filled.toolProfiles.brush.opacity = 1
        selectShownSquare(filled)
        filled.fillSelection()
        XCTAssertTrue(try storedInk(filled, 40, 95), "Fill painted nowhere the loop is shown")
        XCTAssertFalse(try storedInk(filled, 140, 95), "Fill painted at the pen's own coordinates, a pose away")
    }

    /// **Fill on a vector selection** goes through the same pull-back: the element it lays down is
    /// shown where the loop was drawn, not a pose away from it.
    func testFillOnAVectorSelectionUnderAMoveLayerIsShownInsideTheLoop() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 80, y: 0))
        let loop = CGRect(x: 110, y: 30, width: 40, height: 20)
        fx.manager.selection = Selection(path: CGPath(rect: loop, transform: nil), bounds: loop)
        fx.manager.fillSelection()
        let element = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.last, "Fill laid nothing down")
        let onScreen = try XCTUnwrap(shown(element, in: fx.manager, layer: fx.ink).fill?.cgPath)
        let box = onScreen.boundingBoxOfPath
        XCTAssertEqual(box.minX, loop.minX, accuracy: 1, "the fill is not shown inside the loop")
        XCTAssertEqual(box.width, loop.width, accuracy: 1)
        XCTAssertEqual(box.minY, loop.minY, accuracy: 1)
    }

    /// **The wand reads what is shown**, so the region it selects is where the artist tapped.
    func testTheMagicWandUnderAMoveLayerSelectsTheShownSquare() throws {
        let manager = pixelsUnderMove()
        manager.finishAutomaticSelection(at: CGPoint(x: 120, y: 120))
        let bounds = try XCTUnwrap(manager.selection?.bounds, "the wand selected nothing")
        XCTAssertEqual(bounds.minX, 100, accuracy: 1.5, "the selection is not where the square is shown")
        XCTAssertEqual(bounds.width, 40, accuracy: 1.5)
    }

    // MARK: - The Add menu's objects and the wand on a vector layer

    private let slide80 = CGAffineTransform(translationX: 80, y: 0)

    /// **A rectangle dragged out on a vector layer is shown where the pen put it.** The shape is made in
    /// canvas points, so it is written through the pose's inverse like every other input — without it
    /// the stored square is where the pen was and the Move layer then shows it 80 points right.
    func testADraggedRectangleOnAVectorLayerUnderAMoveLayerIsShownWhereThePenPutIt() throws {
        let fx = layerUnderMove(slide80)
        let artwork = try XCTUnwrap(fx.manager.artworkRect)
        XCTAssertTrue(fx.manager.dragOut(.rectangle, from: CGPoint(x: artwork.midX, y: artwork.midY),
                                         to: CGPoint(x: artwork.midX + 60, y: artwork.midY)))
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.last, "no shape was laid down")
        let onScreen = try XCTUnwrap(shown(stored, in: fx.manager, layer: fx.ink).fill?.cgPath).boundingBoxOfPath
        XCTAssertEqual(onScreen.midX, artwork.midX, accuracy: 1, "the rectangle is shown a pose away from where it was dragged")
        XCTAssertEqual(onScreen.midY, artwork.midY, accuracy: 1)
        XCTAssertEqual(onScreen.width, 120, accuracy: 1, "…and at the size it was dragged to")
    }

    /// **The same on a pixel layer**, where the shape is painted into the cel's own pixels: stored 80
    /// points left of where it was dragged, which is where the Move layer carries it back from.
    func testADraggedEllipseOnARasterLayerUnderAMoveLayerIsPaintedWhereItIsShown() throws {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.size
        manager.addLayer(name: "ink")
        manager.addTransformLayer(name: "move")
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: Self.box, mappedBy: slide80), mode: .move)
        manager.currentLayerIndex = 0
        manager.brushColor = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
        manager.toolProfiles.brush.opacity = 1

        XCTAssertTrue(manager.dragOut(.ellipse, from: CGPoint(x: 128, y: 128), to: CGPoint(x: 188, y: 128)))

        XCTAssertTrue(try storedInk(manager, 128 - 80, 128), "the ellipse was not painted where the Move layer shows it")
        XCTAssertFalse(try storedInk(manager, 128, 128), "the ellipse was painted where it was dragged, a pose away")
    }

    /// **A gradient is carried whole**: the path *and* the two ends of its ramp go through the pose's
    /// inverse, so shown it still spans from where the pen went down to where it was lifted — under a
    /// slide, a turn and a scale at once, where a path mapped alone would leave the ramp a pose away
    /// from its own shape.
    func testADraggedGradientUnderAMoveLayerIsShownSpanningTheDragWithItsRampIntact() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 30, y: 10).rotated(by: 0.3).scaledBy(x: 1.4, y: 1.4))
        let artwork = try XCTUnwrap(fx.manager.artworkRect)
        let from = CGPoint(x: artwork.minX, y: artwork.midY), to = CGPoint(x: artwork.maxX, y: artwork.midY)
        XCTAssertTrue(fx.manager.dragOut(.gradient, from: from, to: to))
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.elements.last, "no gradient was laid down")
        let onScreen = try XCTUnwrap(shown(stored, in: fx.manager, layer: fx.ink).fill)
        let box = try XCTUnwrap(onScreen.cgPath).boundingBoxOfPath
        XCTAssertEqual(box.minX, artwork.minX, accuracy: 1, "the gradient is not shown where it was dragged")
        XCTAssertEqual(box.width, artwork.width, accuracy: 1)
        XCTAssertEqual(box.height, artwork.height, accuracy: 1)
        let ramp = try XCTUnwrap(onScreen.gradient)
        assertSame(ramp.from, from, "the ramp starts away from where the pen went down")
        assertSame(ramp.to, to, "the ramp ends away from where the pen was lifted")
    }

    // MARK: - Placed pictures, pasted pictures and screens

    private func pictureOfShape(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// **A picture dragged out under a Move layer is shown where the pen put it** — TODO (149)'s
    /// follow-up. The picture is made in canvas points, so it is written through the pose's inverse like
    /// every other input: stored at the pen it is shown a pose away. Under a slide, a turn and a scale at
    /// once it is still shown centred on the press, as wide as the drag made it, and upright.
    func testADraggedPictureUnderAMoveLayerIsShownCentredOnThePressAtTheDraggedWidthAndUpright() throws {
        let fx = layerUnderMove(CGAffineTransform(translationX: 30, y: 10).rotated(by: 0.3).scaledBy(x: 1.4, y: 1.4))
        let picture = pictureOfShape(width: 40, height: 10)
        let press = CGPoint(x: 100, y: 90)
        XCTAssertTrue(fx.manager.dragOut(.media(PrimedMedia(source: .image(picture), displaySize: picture.size)),
                                         from: press, to: CGPoint(x: 110, y: 92)))   // half height 2.5 at aspect 4: 20 wide
        let stored = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.images.first, "no picture was laid down")
        XCTAssertNotEqual(stored.transform.position, press, "nothing was pulled back through the pose")
        let onScreen = try XCTUnwrap(shown(.image(stored), in: fx.manager, layer: fx.ink).image)
        assertSame(onScreen.transform.position, press, "the picture is shown a pose away from the press")
        XCTAssertEqual(onScreen.transform.scale * 40, 20, accuracy: 0.01, "…and at the width it was dragged to")
        XCTAssertEqual(onScreen.transform.rotation, 0, accuracy: 1e-6, "…and upright")
    }

    /// **A pasted picture is shown centred on the canvas**, held in the Move box where the artist sees
    /// it — Actions → Paste's `insertImage` shared the defect, and a second paste cascades by the same
    /// 24 canvas points *as shown*.
    func testAPastedPictureUnderAMoveLayerIsShownCentredOnTheCanvas() throws {
        let fx = layerUnderMove(slide80)
        let canvasCentre = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        XCTAssertTrue(fx.manager.insertImage(pictureOfShape(width: 40, height: 10)))
        XCTAssertTrue(fx.manager.insertImage(pictureOfShape(width: 40, height: 10)))
        let images = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector?.images)
        XCTAssertEqual(images.count, 2, "Setup: both pastes landed")
        let first = try XCTUnwrap(shown(.image(images[0]), in: fx.manager, layer: fx.ink).image)
        let second = try XCTUnwrap(shown(.image(images[1]), in: fx.manager, layer: fx.ink).image)
        assertSame(first.transform.position, canvasCentre, "the first paste is not shown at the canvas's centre")
        assertSame(second.transform.position, CGPoint(x: canvasCentre.x + 24, y: canvasCentre.y + 24),
                   "the second is not cascaded 24 canvas points as the artist sees it")
    }

    /// **A screen inserted under a Move layer is shown centred too** — Stream Screen is the same
    /// centred placement in a layer of its own.
    func testAStreamInsertedUnderAMoveLayerIsShownCentredOnTheCanvas() throws {
        let fx = layerUnderMove(slide80)
        let status = StreamStatus(source: StreamStatus.Source(kind: "window", name: "Blender"),
                                  width: 160, height: 90, fps: 30, streaming: true)
        let inserted = try XCTUnwrap(fx.manager.insertStream(host: "laptop", port: 47301, status: status))
        let layer = fx.manager.currentLayerIndex
        let stored = try XCTUnwrap(fx.manager.layers[layer].cels[0].vector?.streams.first { $0.id == inserted.id })
        let onScreen = try XCTUnwrap(shown(.stream(stored), in: fx.manager, layer: layer).stream)
        assertSame(onScreen.transform.position, CGPoint(x: Self.size.width / 2, y: Self.size.height / 2),
                   "the screen is shown a pose away from the canvas's centre")
    }

    /// **The wand on a vector layer reads the picture the Move layer shows.** Two strokes stored on
    /// the left and carried 80 points right; a tap on the first *where it is shown* selects that
    /// stroke's shape. Read against the picture before the Move layer carried it, the tap lands on
    /// paper and the wand selects all of that.
    func testTheMagicWandOnAVectorLayerUnderAMoveLayerSelectsTheShownStroke() throws {
        let fx = layerUnderMove(slide80)
        let vector = try XCTUnwrap(fx.manager.layers[fx.ink].cels[0].vector)
        for y: CGFloat in [100, 30] {
            vector.addStroke(VectorStroke(brush: BrushLibrary.roundHard,
                                          color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 8,
                                          opacity: 1, samples: StrokeSamples(points: [CGPoint(x: 30, y: y),
                                                                                      CGPoint(x: 70, y: y)])))
        }

        fx.manager.finishAutomaticSelection(at: CGPoint(x: 130, y: 100))

        let bounds = try XCTUnwrap(fx.manager.selection?.bounds, "the wand selected nothing")
        XCTAssertEqual(bounds.minX, 106, accuracy: 3, "the selection is not where the stroke is shown")
        XCTAssertEqual(bounds.maxX, 154, accuracy: 3)
        XCTAssertEqual(bounds.height, 8, accuracy: 3, "the wand took the paper around the stroke, not the stroke")
    }
}
