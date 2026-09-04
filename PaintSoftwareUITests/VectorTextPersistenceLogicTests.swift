import XCTest

/// Pure-logic tests for **`ADD_TEXT.md` stage 3's one promise**: text put on a vector layer is still
/// a text object afterwards — not a picture of one — and it is still the *same* object, in the same
/// place in the display list, after a save and a load.
///
/// That is the whole reason the stage exists, so the round trip here is deliberately the long one:
/// a `VectorCanvas` holding a text element among strokes and fills → `VectorCanvasData` → JSON bytes
/// → `VectorCanvasData` → a `VectorCanvas` again → and then *edited*, to prove the reloaded element
/// still upserts in place rather than landing as a new object on top. A test that stopped at
/// "decoded without throwing" would pass for a design that had baked the glyphs.
///
/// Assertions are on identities and z-order rather than on measured glyph geometry, for
/// `TextLayoutLogicTests`' stated reason: "this string is 412.5 points wide" is a claim about a font
/// file Apple revises, not about this code.
///
/// Lives in `PaintSoftwareUITests` with the other `*LogicTests` and needs no simulator gesture —
/// `Engine/VectorLayer.swift` and `Engine/TextObject.swift` are compiled into this target directly
/// (see `BrushEngineLogicTests`' header for why `@testable import` cannot work here).
final class VectorTextPersistenceLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 64, height: 64)

    // MARK: - Fixtures

    private static func testBrush() -> Brush {
        Brush(name: "Test", tip: .round, size: 20, opacity: 1, flow: 1,
              spacingFraction: 0.1, hardness: 1, stabilization: 0, scatter: 0,
              rotationJitter: 0, dynamics: .fixed, blendMode: .normal)
    }

    private func stroke() -> VectorStroke {
        VectorStroke(brush: Self.testBrush(),
                     color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                     size: 20, opacity: 1,
                     samples: [VectorSample(x: 8, y: 8, pressure: 1),
                               VectorSample(x: 40, y: 40, pressure: 1)])
    }

    private func fill() -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: Self.canvasSize), transform: nil),
                          color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1))
    }

    /// Every field set away from its default, and every number exactly representable as a `Double`,
    /// so the round-trip assertion can be plain equality on the whole value rather than a
    /// field-by-field tolerance walk that would quietly stop covering a field somebody adds.
    private func text(_ string: String = "Hello", id: UUID = UUID()) -> VectorTextElement {
        let typography = Typography(pointSize: 37.5, tracking: 2.25, lineHeightMultiple: 1.5,
                                    lineSpacing: 3.5, paragraphSpacing: 12.5, alignment: .center)
        let recipe = TextRecipe(string: string,
                                font: FontDescriptor(familyName: "Helvetica Neue",
                                                     faceName: "HelveticaNeue-BoldItalic",
                                                     packID: "google-noto", isBold: true, isItalic: true),
                                typography: typography,
                                color: CodableColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5),
                                opacity: 0.75)
        // A rotated quad rather than an upright one, so the corners cannot round-trip "correctly" by
        // being re-derived from `size` — `TextFrame.init(from:)` repairs a frame whose corner count is
        // wrong by doing exactly that, and this is what tells a repair apart from a real decode.
        let frame = TextFrame(size: CGSize(width: 30, height: 10),
                              corners: [CGPoint(x: 20, y: 8), CGPoint(x: 44, y: 20),
                                        CGPoint(x: 39, y: 30), CGPoint(x: 15, y: 18)],
                              mode: .affine, autoSize: false)
        return VectorTextElement(id: id, recipe: recipe, frame: frame,
                                 motionGroupID: UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    }

    /// One-word tag per kind, so an expected z-order reads as a literal in the assertions.
    private func kinds(_ elements: [VectorElement]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .text: return "text"
            case .video: return "video"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    private func kinds(_ elements: [VectorCanvasData.ElementData]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .text: return "text"
            case .video: return "video"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    private func reload(_ payload: VectorCanvasData) throws -> VectorCanvasData {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(VectorCanvasData.self, from: data)
    }

    // MARK: - Element → JSON → element

    func testTextElementRoundTripsThroughJSONUnchanged() throws {
        let original = text()
        let payload = VectorCanvasData(elements: [.text(original)], transform: [1, 0, 0, 1, 0, 0])
        let decoded = try reload(payload)

        XCTAssertTrue(decoded.decodeReport.isClean,
                      "A text element is a kind this build knows; nothing should be reported dropped.")
        XCTAssertEqual(decoded.texts.count, 1)
        // Whole-value equality, not a field walk: `VectorTextElement` is `Equatable` all the way down,
        // so a field added later is covered by this line without anybody remembering to extend it.
        XCTAssertEqual(decoded.texts.first, original)
    }

    /// The specific fields most likely to be lost by a synthesized decoder that ignores property
    /// defaults, spelled out so a failure names what went missing rather than saying "not equal".
    func testTheRecipeAndTheFrameSurviveFieldByField() throws {
        let original = text("Two\nLines")
        let decoded = try reload(VectorCanvasData(elements: [.text(original)], transform: []))
        let element = try XCTUnwrap(decoded.texts.first)

        XCTAssertEqual(element.id, original.id)
        XCTAssertEqual(element.motionGroupID, original.motionGroupID)
        XCTAssertEqual(element.recipe.string, "Two\nLines")
        XCTAssertEqual(element.recipe.font.familyName, "Helvetica Neue")
        XCTAssertEqual(element.recipe.font.faceName, "HelveticaNeue-BoldItalic")
        XCTAssertEqual(element.recipe.font.packID, "google-noto",
                       "The pack qualifier is what makes a missing font diagnosable rather than mysterious.")
        XCTAssertTrue(element.recipe.font.isBold)
        XCTAssertTrue(element.recipe.font.isItalic)
        XCTAssertEqual(element.recipe.typography.pointSize, 37.5)
        XCTAssertEqual(element.recipe.typography.tracking, 2.25)
        XCTAssertEqual(element.recipe.typography.lineHeightMultiple, 1.5)
        XCTAssertEqual(element.recipe.typography.alignment, .center)
        XCTAssertEqual(element.recipe.opacity, 0.75)
        XCTAssertEqual(element.frame.size, CGSize(width: 30, height: 10))
        XCTAssertEqual(element.frame.corners, original.frame.corners,
                       "A rotated quad must come back as itself, not be repaired into an upright box.")
        XCTAssertFalse(element.frame.autoSize,
                       "`autoSize` is a stored bit; a sized box that reloads as pristine would start growing again.")
    }

    /// The on-disk discriminator, asserted as the literal string rather than by decoding it back.
    ///
    /// It is the contract with builds that do not have this feature: an older one meets `"text"`,
    /// classifies it as an *unknown kind* rather than a malformed element, and loses that element
    /// alone — which is the whole point of stage 2's per-element decode. Rename it and that promise
    /// silently becomes "the cel decodes as something else".
    func testTheDiscriminatorIsTheStringText() throws {
        let data = try JSONEncoder().encode(VectorCanvasData(elements: [.text(text())], transform: []))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try XCTUnwrap(json["elements"] as? [[String: Any]])
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0]["kind"] as? String, "text")
        XCTAssertNotNil(elements[0]["text"], "The payload rides under its own key, inline — no sidecar file.")
    }

    /// A text entry this build *does* know but cannot read is a defect, and is counted apart from a
    /// newer-file discriminator. Stage 2's classifier, exercised through the new kind.
    func testAMalformedTextCostsThatElementAndNothingElse() throws {
        let payload = VectorCanvasData(elements: [.stroke(stroke()), .text(text()), .fill(fill())],
                                       transform: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(payload))
                                    as? [String: Any])
        var elements = try XCTUnwrap(json["elements"] as? [[String: Any]])
        elements[1]["text"] = ["recipe": "not an object"]
        json["elements"] = elements
        let surgery = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: surgery)
        XCTAssertEqual(kinds(decoded.elements), ["stroke", "fill"])
        XCTAssertEqual(decoded.decodeReport.malformedCount, 1)
        XCTAssertTrue(decoded.decodeReport.unknownKinds.isEmpty,
                      "`text` is a kind this build has; a broken payload under it is a defect, not a version gap.")
    }

    // MARK: - Z-order

    /// The stage's other named test: **an upsert at index does not move the object.**
    ///
    /// Re-typing a label that sits behind a drawing must not pull it in front of the drawing, which
    /// is exactly what remove-then-add would do.
    func testUpsertReplacesInPlaceAndKeepsZOrder() {
        let original = text("before")
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: [.fill(fill()), .text(original), .stroke(stroke())])
        XCTAssertEqual(kinds(canvas.elements), ["fill", "text", "stroke"])

        var edited = original
        edited.recipe.string = "after"
        canvas.upsertText(edited)

        XCTAssertEqual(kinds(canvas.elements), ["fill", "text", "stroke"],
                       "An upsert must not re-stack the display list.")
        XCTAssertEqual(canvas.elements[1].text?.id, original.id)
        XCTAssertEqual(canvas.elements[1].text?.recipe.string, "after")
        XCTAssertEqual(canvas.texts.count, 1, "An upsert replaces; it does not add a second copy.")
    }

    /// The other half of the same rule: an object nobody has seen before goes on top of what is
    /// already there, which is what the artist just placed.
    func testANewTextIsAppendedOnTop() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill()), .stroke(stroke())])
        canvas.upsertText(text("fresh"))
        XCTAssertEqual(kinds(canvas.elements), ["fill", "stroke", "text"])
    }

    /// Numbering `Kind.text` below `.stroke` is what keeps this true: a brush stroke drawn after the
    /// text still lands at the very end of the list, above both the text and any `.erase` punch,
    /// which is the invariant `insertionIndex` exists to protect.
    func testAStrokeAddedAfterTextStillLandsOnTop() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill())])
        canvas.upsertText(text())
        canvas.addStroke(stroke())
        XCTAssertEqual(kinds(canvas.elements), ["fill", "text", "stroke"])
    }

    func testZOrderSurvivesTheSaveLoadRoundTrip() throws {
        let element = text()
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: [.fill(fill()), .text(element), .stroke(stroke())])
        let reloaded = try reload(VectorCanvasData(from: canvas, imageFileNames: [:]))
        XCTAssertEqual(kinds(reloaded.elements), ["fill", "text", "stroke"])
        XCTAssertEqual(reloaded.texts.first?.id, element.id)
    }

    // MARK: - Still editable after a reload

    /// **The stage's promise, end to end.** Save a canvas with text on it, load it back, and then
    /// edit the loaded object: it must upsert in place, keep its id, and keep its z-position.
    ///
    /// Everything short of the final edit would also pass for a design that stored a picture of the
    /// text beside the recipe; the edit is what proves the reloaded thing is the object itself.
    func testTextIsStillEditableAfterASaveAndLoad() throws {
        let element = text("original")
        let saved = VectorCanvas(size: Self.canvasSize,
                                 elements: [.fill(fill()), .text(element), .stroke(stroke())])
        let payload = try reload(VectorCanvasData(from: saved, imageFileNames: [:]))
        let loaded = VectorCanvas(size: Self.canvasSize,
                                  elements: payload.canvasSpaceElements(resolvingImages: { _ in nil },
                                                                        resolvingVideos: { _ in nil }))

        // 1. It came back as a text object, not as pixels, and as the same one.
        let reopened = try XCTUnwrap(loaded.topmostText(atCanvasPoint: CGPoint(x: 30, y: 18)))
        XCTAssertEqual(reopened.id, element.id)
        XCTAssertEqual(reopened.recipe.string, "original")

        // 2. Retyping it — a whole edit session in one line — lands back on the same element.
        var retyped = reopened
        retyped.recipe.string = "retyped, and still the same object"
        retyped.recipe.typography.pointSize = 96
        loaded.upsertText(retyped)

        XCTAssertEqual(kinds(loaded.elements), ["fill", "text", "stroke"])
        XCTAssertEqual(loaded.texts.count, 1)
        XCTAssertEqual(loaded.texts.first?.id, element.id)
        XCTAssertEqual(loaded.texts.first?.recipe.string, "retyped, and still the same object")

        // 3. And the edit itself survives a second save/load, so the loop closes.
        let again = try reload(VectorCanvasData(from: loaded, imageFileNames: [:]))
        XCTAssertEqual(again.texts.first?.recipe.string, "retyped, and still the same object")
        XCTAssertEqual(again.texts.first?.recipe.typography.pointSize, 96)
        XCTAssertEqual(again.texts.first?.id, element.id)
    }

    // MARK: - The edit session's contract with the render cache

    /// `ADD_TEXT.md` §1: the committed element is **suppressed** from the flatten, never lifted out
    /// of the array. The persisted source of truth must never momentarily lack an object the artist
    /// has already committed.
    func testEditingElementIDSuppressesWithoutLifting() {
        let element = text()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.text(element), .stroke(stroke())])
        canvas.editingElementID = element.id

        XCTAssertEqual(kinds(canvas.elements), ["text", "stroke"],
                       "Suppression is a flag on the canvas, not a splice of the display list.")
        XCTAssertEqual(VectorCanvasData(from: canvas, imageFileNames: [:]).texts.count, 1,
                       "A save taken mid-edit must still contain the object.")
    }

    /// §4 rule 4: **exactly two invalidations per session**, at open and at commit. Every bump
    /// cascades into `RasterizeKey`, `LayerContentVersion`, `SandwichKey` and both upload caches,
    /// each costing a canvas-sized flatten and an LRU eviction, so "one more" is not free.
    func testASessionCostsExactlyTwoInvalidations() {
        let element = text("before")
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.text(element)])
        let start = canvas.version

        canvas.editingElementID = element.id                        // open
        var edited = element
        edited.recipe.string = "after"
        canvas.commitTextEdit(editingID: element.id, element: edited)  // commit

        XCTAssertEqual(canvas.version - start, 2)
        XCTAssertNil(canvas.editingElementID, "Committing is what ends the suppression.")
        XCTAssertEqual(canvas.texts.first?.recipe.string, "after")
    }

    /// Emptying the box deletes the object. Leaving an empty one behind would leave an invisible
    /// element the artist cannot select to get rid of.
    func testCommittingAnEmptiedBoxDeletesTheObject() {
        let element = text()
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill()), .text(element)])
        canvas.editingElementID = element.id

        XCTAssertTrue(canvas.commitTextEdit(editingID: element.id, element: nil))
        XCTAssertEqual(kinds(canvas.elements), ["fill"])
        XCTAssertNil(canvas.editingElementID)
    }

    /// A box placed and never typed into changes nothing, so it must register nothing — the caller
    /// keys its undo step off this answer.
    func testCommittingAnEmptyNewBoxReportsNoChange() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill())])
        XCTAssertFalse(canvas.commitTextEdit(editingID: nil, element: nil))
        XCTAssertEqual(kinds(canvas.elements), ["fill"])
    }

    // MARK: - The layer's own transform

    /// Storage is local space and `render()` applies the layer transform afterwards, so a frame
    /// captured where the finger was has to be mapped in — the same rule `addStroke(canvasSpaceStroke:)`
    /// and `addFill(canvasSpacePath:)` already follow. A round trip through both directions is exact.
    func testCanvasSpaceAndLocalSpaceRoundTrip() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [],
                                  transform: CGAffineTransform(translationX: 100, y: -40)
                                    .concatenating(CGAffineTransform(scaleX: 2, y: 2)))
        let element = text()
        let local = canvas.localText(fromCanvas: element)
        let back = canvas.canvasText(fromLocal: local)

        XCTAssertNotEqual(local.frame.corners, element.frame.corners,
                          "A non-identity layer transform must actually move the stored frame.")
        for (a, b) in zip(back.frame.corners, element.frame.corners) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
        XCTAssertEqual(back.frame.size.width, element.frame.size.width, accuracy: 1e-9)
        XCTAssertEqual(back.recipe.typography.pointSize, element.recipe.typography.pointSize,
                       accuracy: 1e-9,
                       "The point size travels with the box, or a scaled layer re-lays the glyphs out wrong.")
    }
}
