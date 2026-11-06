import XCTest
import UIKit
import ImageIO

/// **Select → Duplicate on a vector layer produces a vector layer** — TODO item (33), the owner's
/// *"When I select and duplicate, it does not support vector (the duplicated selection is a raster
/// layer not a vector)."*
///
/// `beginDuplicate()` had no layer-kind check: it rasterized the cel, masked the pixels and inserted
/// a `.raster` layer. The copy *looked* right, which is why it survived — the original stayed vector,
/// nothing said anything, and the artist found out when they tried to erase or re-cut the copy.
///
/// The native clipboard shares Duplicate's membership/pose preparation and layer/Move insertion.
/// Clipboard checks also pin drawn order and resource placement; editability still needs geometry.
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
        manager.selection = Selection(path: path, bounds: rect)
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
    @MainActor
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
    }

    /// Duplicate is a copy, not a cut: whatever the loop caught has to still be on the layer it came
    /// from. The vector arm builds its copy out of `splitForLassoMove`'s return value and never
    /// assigns it back, which is the whole of how it differs from Move — this is the assertion that
    /// says so.
    @MainActor
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
    @MainActor
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
    @MainActor
    func testTheDuplicateArrivesHeldInTheMoveBoxOnTheNewLayer() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32)))
        select(manager, layerIndex, CGRect(x: 10, y: 22, width: 44, height: 20))

        manager.beginDuplicate()

        guard let copy = copyLayer(manager, above: layerIndex), let float = manager.vectorFloat else {
            return XCTFail("Duplicate should leave the copy floating, the way the raster arm does")
        }
        XCTAssertEqual(float.parts[0].layerID, copy.id, "The box holds the copy, not the original")
        XCTAssertEqual(manager.currentLayerIndex, layerIndex + 1, "and the copy is the active layer")
        XCTAssertNil(manager.selection, "Duplicate spends its selection at the lift (LASSO_MOVE §5.6)")
        XCTAssertNil(manager.floatingPiece,
                     "The raster floating piece is the old arm; a vector duplicate must not raise one")
    }

    /// Settling the box has to leave the copy on the layer. A float suppresses its ids out of the
    /// layer's own render, so a duplicate whose suppression is never cleared is a new layer that is in
    /// the saved document and draws nothing — a copy the artist cannot see and cannot get back.
    @MainActor
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
    @MainActor
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
    @MainActor
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

    @MainActor
    func testClipboardPastesAnIndependentEditableDrawingWithItsOrderPixelsSpanAndUndo() throws {
        let pasteboard = UIPasteboard.general
        pasteboard.items = []
        defer { pasteboard.items = [] }
        let (source, index, vector) = fixture()
        let animationGroup = UUID(), motionGroup = UUID()
        source.animationGroups = [AnimationGroup(id: animationGroup, displayName: "Source pose", tagColor: black())]
        source.motionGroups = [MotionGroup(id: motionGroup, displayName: "Source correspondence", tagColor: black())]
        var fill = VectorFillElement(path: CGPath(rect: CGRect(x: 6, y: 6, width: 48, height: 48), transform: nil),
                                     color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        var line = stroke(from: CGPoint(x: 12.125, y: 20.125), to: CGPoint(x: 46.125, y: 20.125), size: 6)
        var text = VectorTextElement(recipe: TextRecipe(string: "A"),
                                    frame: TextFrame(origin: CGPoint(x: 8, y: 30), size: CGSize(width: 20, height: 20)))
        let raw = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied:
            [255, 0, 0, 255, 0, 0, 255, 255, 0, 255, 0, 255, 255, 255, 0, 255, 0, 255, 255, 255, 255, 0, 255, 255],
            width: 3, height: 2))
        var admitsEncoding = true
        let pictureOwner = RasterResidency(budgetBytes: 1024 * 1024, hasHeadroom: { _ in admitsEncoding })
        var picture = VectorImageElement(source: try CanvasFixture.placedSource(
            UIImage(cgImage: raw, scale: 2, orientation: .right), using: pictureOwner),
            transform: LayerTransform(position: CGPoint(x: 42, y: 40), scale: 10, rotation: 0))
        fill.animationGroupID = animationGroup
        line.animationGroupID = animationGroup; line.motionGroupID = motionGroup
        text.animationGroupID = animationGroup; text.motionGroupID = motionGroup
        picture.animationGroupID = animationGroup
        vector.restoreElements([.fill(fill), .stroke(line), .text(text), .image(picture)], changedInk: nil)
        let sourceIDs = Set(vector.elements.map(\.id))
        let ownedPixelsBefore = pictureOwner.usage
        let expected = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
        source.layers[index].cels[0].frameCount = 3
        select(source, index, CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertTrue(source.copySelectionToPasteboard())
        let native = try XCTUnwrap(pasteboard.data(forPasteboardType: SelectionClipboard.type))
        XCTAssertNotNil(pasteboard.image?.cgImage, "other apps still receive a picture")
        admitsEncoding = false
        XCTAssertFalse(source.copySelectionToPasteboard(), "the portable PNG read must obtain its working reservation")
        XCTAssertEqual(pasteboard.data(forPasteboardType: SelectionClipboard.type), native,
                       "refused encoder admission preserves the complete previous clipboard")
        admitsEncoding = true
        XCTAssertTrue(source.cutSelectionToPasteboard(), "fresh native picture Copy and Cut both complete without a save or retry")
        XCTAssertTrue(vector.elements.isEmpty, "Cut removes the complete selected native drawing")
        XCTAssertEqual(pictureOwner.usage.pixelBytes, ownedPixelsBefore.pixelBytes, "portable export keeps the native pixel owner")
        XCTAssertEqual(pictureOwner.usage.reservedCheckpointBytes, ownedPixelsBefore.reservedCheckpointBytes,
                       "portable export does not replace native ownership with a durable PNG checkpoint")
        XCTAssertEqual(pictureOwner.usage.workingBytes, 0, "portable export releases its encoder reservation")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pictureOwner.storage.url.path),
                       "Copy and Cut schedule or write no source checkpoint files")
        // The original layer/document and even the fallback picture are unnecessary for native Paste.
        source.layers.removeAll()
        pasteboard.setItems([[SelectionClipboard.type: native]])
        let destination = CanvasFixture.manager(layerCount: 1)
        destination.currentFrame = 5
        destination.history.removeAll()
        XCTAssertNil(destination.pasteSelectionFromPasteboard())
        destination.commitVectorFloatIfNeeded()
        let pasted = try XCTUnwrap(destination.layers.last?.cels.first)
        let copied = try XCTUnwrap(pasted.vector)
        XCTAssertEqual(destination.layers.count, 2, "Paste always creates its own layer")
        XCTAssertEqual([pasted.startFrame, pasted.frameCount], [5, 3], "current destination time and copied duration")
        XCTAssertEqual(copied.elements.map { $0.fill != nil ? "fill" : $0.stroke != nil ? "stroke" : $0.text != nil ? "text" : "image" },
                       ["fill", "stroke", "text", "image"], "all supported kinds retain their drawn order")
        XCTAssertEqual(try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(copied.render()?.cgImage))), expected,
                       "native geometry and the oriented scale-2 picture draw exactly as copied")
        XCTAssertEqual(copied.strokes.first?.samples.positions, line.samples.positions, "the pasted line is editable geometry")
        XCTAssertTrue(sourceIDs.isDisjoint(with: Set(copied.elements.map(\.id))), "each incoming object has a fresh identity")
        XCTAssertFalse(copied.elements.contains { $0.isMoved(by: .group(animationGroup)) }, "incoming objects leave the source animation group")
        XCTAssertNil(copied.strokes.first?.motionGroupID, "the incoming stroke leaves the source interpolation group")
        XCTAssertNil(copied.elements.compactMap(\.text).first?.motionGroupID, "the incoming text leaves the source interpolation group")
        XCTAssertEqual(destination.history.undoStack.count, 1, "the insertion is one priced history action")
        let minimumRetainedBytes = 4096 + picture.source.logicalPayloadBytes + line.samples.positions.count * MemoryLayout<CGPoint>.stride
            + fill.pathData.count + text.recipe.string.utf8.count
        XCTAssertGreaterThanOrEqual(destination.history.currentCost, minimumRetainedBytes,
                                    "the production Undo entry charges its retained picture, samples, fill and text")
        destination.undo()
        XCTAssertEqual(destination.layers.count, 1, "Undo removes the pasted layer")
        destination.redo()
        XCTAssertEqual(try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(destination.layers.last?.cels.first?.vector?.render()?.cgImage))), expected,
                       "Redo restores the complete ordered native drawing")
        destination.history.maxCost = minimumRetainedBytes - 1
        XCTAssertNil(destination.pasteSelectionFromPasteboard())
        destination.commitVectorFloatIfNeeded()
        XCTAssertTrue(destination.history.undoStack.isEmpty, "the actual retained-byte budget trims the oversized pasted actions")
        XCTAssertEqual(destination.history.currentCost, 0, "trimmed actions retain no Undo payload charge")
    }

    @MainActor
    func testMalformedNativeClipboardRefusesBeforeSettlingAFloatAndNeverUsesItsPicture() throws {
        let pasteboard = UIPasteboard.general
        pasteboard.items = []
        defer { pasteboard.items = [] }
        let (manager, index, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32)))
        select(manager, index, CGRect(x: 10, y: 22, width: 44, height: 20))
        manager.beginDuplicate()
        let floatID = try XCTUnwrap(manager.vectorFloat).parts[0].celID
        let layers = manager.layers.count, steps = manager.history.undoStack.count
        let valid = try SelectionClipboard.encode(vector.elements, canvasSize: vector.size, frameCount: 3)
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        future["version"] = SelectionClipboard.currentVersion + 1
        let fallback = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        for malformed in [Data("broken".utf8), try JSONSerialization.data(withJSONObject: future)] {
            pasteboard.setItems([[SelectionClipboard.type: malformed, "com.apple.uikit.image": fallback]])
            XCTAssertNotNil(manager.pasteSelectionFromPasteboard(), "a recognized damaged/future drawing visibly refuses")
            XCTAssertEqual(manager.vectorFloat?.parts[0].celID, floatID, "a refused Paste does not settle the artist's Move")
            XCTAssertEqual([manager.layers.count, manager.history.undoStack.count], [layers, steps], "no flattened layer or Undo step")
            XCTAssertEqual(pasteboard.data(forPasteboardType: SelectionClipboard.type), malformed, "Paste never rewrites the clipboard")
        }
        XCTAssertThrowsError(try SelectionClipboard.prepare(Data(repeating: 0, count: SelectionClipboard.maximumBytes + 1)),
                             "over-budget data is rejected before JSON or pixel decoding")
    }

    @MainActor
    func testNativeClipboardRedeemsBrushesAndPreflightsCompletePictureResources() throws {
        let line = stroke(from: CGPoint(x: 12, y: 20), to: CGPoint(x: 44, y: 20))
        let native = try SelectionClipboard.encode([.stroke(line)], canvasSize: CanvasFixture.canvasSize, frameCount: 2)
        let envelope = try JSONDecoder().decode(SelectionClipboard.self, from: native)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: native) as? [String: Any])
        var table = try XCTUnwrap(object["brushes"] as? [String: Any])
        var entries = try XCTUnwrap(table["entries"] as? [[String: Any]])
        entries[0]["ref"] = UInt32.max - 1
        table["entries"] = entries; object["brushes"] = table
        var drawing = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.drawing) as? [String: Any])
        var elements = try XCTUnwrap(drawing["elements"] as? [[String: Any]])
        var payload = try XCTUnwrap(elements[0]["stroke"] as? [String: Any])
        payload["brush"] = UInt32.max - 1; elements[0]["stroke"] = payload; drawing["elements"] = elements
        object["drawing"] = try JSONSerialization.data(withJSONObject: drawing).base64EncodedString()
        let prepared = try SelectionClipboard.prepare(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(prepared.elements.first?.stroke?.brush, line.brush, "stored numbers are redeemed through this payload's table")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        let picture = VectorImageElement(source: try CanvasFixture.placedSource(image), transform: .identity)
        let complete = try SelectionClipboard.encode([.image(picture)], canvasSize: CanvasFixture.canvasSize, frameCount: 2)
        var broken = try XCTUnwrap(JSONSerialization.jsonObject(with: complete) as? [String: Any])
        broken["images"] = [:]
        XCTAssertThrowsError(try SelectionClipboard.prepare(JSONSerialization.data(withJSONObject: broken)),
                             "a missing required picture refuses the entire native drawing")

        // Valid solid 1-bit PNGs compress to a few KiB. Their real dimensions require more than
        // 64MiB as RGBA: once in one picture, once only after summing two individually valid ones.
        let budgetPNGs: [(width: Int, count: Int, base64: String)] = [
            (8192, 1, """
                iVBORw0KGgoAAAANSUhEUgAAIAAAAAgBAQAAAABt31OqAAAICklEQVR42u3BMQEAAADCoPVPbQsvoAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABOBg3hAAEZ
                usn9AAAAAElFTkSuQmCC
                """),
            (4096, 2, """
                iVBORw0KGgoAAAANSUhEUgAAEAAAAAgBAQAAAABFtRi2AAAEEUlEQVR42u3BMQEAAADCoPVPbQZ/oAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADgMArxAAERgASuAAAAAElFTkSuQmCC
                """)
        ]
        for fixture in budgetPNGs {
            let png = try XCTUnwrap(Data(base64Encoded: fixture.base64, options: .ignoreUnknownCharacters))
            let header = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(header, 0, nil) as? [CFString: Any])
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, fixture.width, "the small PNG really declares its tested width")
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2049, "the small PNG really declares its tested height")
            XCTAssertLessThan(png.count, 4096, "compressed bytes alone cannot catch this decoded-size limit")
            let declaredRGBABytes = fixture.width * 2049 * 4
            XCTAssertGreaterThan(declaredRGBABytes * fixture.count, SelectionClipboard.maximumBytes,
                                 "the complete declared picture set exceeds the decoded budget")
            if fixture.count > 1 {
                XCTAssertLessThan(declaredRGBABytes, SelectionClipboard.maximumBytes,
                                  "each individual picture fits: only their accumulated pixels exceed the budget")
            }
            let refs = (0..<fixture.count).map { n in
                VectorCanvasData.ImageRef(fileName: "picture-\(n).png", x: 32, y: 32, scale: 1, rotation: 0,
                                          aspect: nil, stretchAxis: nil, mirrored: nil, animationGroupID: nil)
            }
            let pictureData = try JSONEncoder().encode(VectorCanvasData(elements: refs.map(VectorCanvasData.ElementData.image), transform: []))
            let resourcePayload = SelectionClipboard(version: SelectionClipboard.currentVersion, frameCount: 1,
                brushes: BrushTable(), drawing: pictureData,
                images: Dictionary(uniqueKeysWithValues: refs.map { ($0.fileName, png) }), textures: [:])
            let tinyOwner = RasterResidency(budgetBytes: 1, hasHeadroom: { _ in true })
            XCTAssertThrowsError(try SelectionClipboard.prepare(JSONEncoder().encode(resourcePayload), using: tinyOwner)) { error in
                XCTAssertTrue(error is SelectionClipboard.Failure,
                              "decoded-size admission refuses the complete resource set before any native pixel admission")
            }
            XCTAssertEqual(tinyOwner.usage.allocations, 0, "an oversized resource set allocates no native picture buffers")
        }
    }

    @MainActor
    func testImportedBrushPixelsTravelWithoutOverwritingACollisionAndFailedInsertionRollsBack() throws {
        let storage = BrushStorage.shared
        let previous = storage.root
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-brush-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage.relocate(to: directory)
        defer { storage.relocate(to: previous); try? FileManager.default.removeItem(at: directory) }
        let tipImage = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 1, y: 1, width: 5, height: 6))
        }
        var line = stroke(from: CGPoint(x: 12, y: 20), to: CGPoint(x: 44, y: 20), size: 12)
        line.brush.tip = try BrushTipImport.importTip(from: tipImage)
        let originalName = try XCTUnwrap(line.brush.tip.importedTextureFileName)
        let vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(line)])
        let expected = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(vector.render()?.cgImage)))
        let native = try SelectionClipboard.encode(vector.elements, canvasSize: vector.size, frameCount: 2)
        let collision = Data("existing artist resource".utf8)
        try storage.write(collision, to: originalName)
        let prepared = try SelectionClipboard.prepare(native)
        let adoptedName = try XCTUnwrap(prepared.elements.first?.stroke?.brush.tip.importedTextureFileName)
        XCTAssertNotEqual(adoptedName, originalName, "different bytes under a used name receive a new name")
        XCTAssertFalse(prepared.installingTextures(then: { false }))
        XCTAssertEqual(storage.read(originalName), collision, "the artist's colliding file is unchanged")
        XCTAssertFalse(storage.contains(adoptedName), "failed insertion removes only its new resource")
        XCTAssertTrue(prepared.installingTextures(then: { true }))
        let copied = VectorCanvas(size: vector.size, elements: prepared.elements)
        XCTAssertEqual(try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(copied.render()?.cgImage))), expected,
                       "the pasted brush uses the embedded original pixels, independent of the collision")
    }

    @MainActor
    func testMixedBackingCopyKeepsTheWholePictureFallbackInsteadOfDroppingItsNativeInk() throws {
        let pasteboard = UIPasteboard.general
        pasteboard.items = []
        defer { pasteboard.items = [] }
        let (manager, index, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 12, y: 20), to: CGPoint(x: 44, y: 20)))
        let backing = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        manager.layers[index].cels[0].bakedImage = try CanvasFixture.placedSource(backing)
        select(manager, index, CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertTrue(manager.copySelectionToPasteboard())
        XCTAssertFalse(pasteboard.contains(pasteboardTypes: [SelectionClipboard.type]), "mixed backing must never become a partial native payload")
        let copied = try XCTUnwrap(pasteboard.image?.cgImage)
        let expected = try XCTUnwrap(PixelOps.rasterize(cel: manager.layers[index].cels[0], canvasSize: CanvasFixture.canvasSize)?.cgImage)
        XCTAssertEqual(CanvasFixture.rgbaBytes(copied), CanvasFixture.rgbaBytes(expected),
                       "the interoperable picture retains both backing and vector ink")
    }

}
