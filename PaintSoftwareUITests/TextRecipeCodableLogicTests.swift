import XCTest

/// Current saved-text requirements, with normal initializer defaults kept separate from decoding.
/// Missing/null required fields must reach the existing element-loss/save-damage owner. Optional
/// font/group references, explicit empty words and unknown extra keys remain legitimate values.
final class TextRecipeCodableLogicTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Damage each real encoded type, not a copied model of its decoder. The same assertion is
    /// exercised for omission and explicit null of every required field; optional references are
    /// checked separately against a healthy complete value.
    private func assertRequiredFields<T: Codable>(_ value: T, keys: [String],
                                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value))
                                        as? [String: Any], file: file, line: line)
        for key in keys {
            for null in [false, true] {
                var damaged = original
                if null { damaged[key] = NSNull() }
                else { damaged.removeValue(forKey: key) }
                let bytes = try JSONSerialization.data(withJSONObject: damaged)
                XCTAssertThrowsError(try decoder.decode(T.self, from: bytes),
                                     "\(T.self).\(key) must reject \(null ? "null" : "omission")",
                                     file: file, line: line)
            }
        }
    }

    func testEveryRequiredSavedTextFieldRejectsOmissionAndNull() throws {
        let recipe = TextRecipe(string: "Keep these words")
        let frame = TextFrame(origin: CGPoint(x: 8, y: 12), size: CGSize(width: 45, height: 30))
        try assertRequiredFields(recipe.font, keys: ["familyName", "isBold", "isItalic"])
        try assertRequiredFields(recipe.typography,
                                 keys: ["pointSize", "tracking", "lineHeightMultiple", "lineSpacing",
                                        "paragraphSpacing", "alignment"])
        try assertRequiredFields(recipe, keys: ["string", "font", "typography", "color", "opacity"])
        try assertRequiredFields(frame, keys: ["size", "corners", "mode", "autoSize"])
        try assertRequiredFields(VectorTextElement(recipe: recipe, frame: frame), keys: ["id", "recipe", "frame"])
    }

    func testExplicitEmptyWordsAndOptionalFontAndGroupReferencesRemainReadable() throws {
        let original = VectorTextElement(recipe: TextRecipe(), frame: TextFrame(origin: .zero, size: .zero))
        let bytes = try encoder.encode(original)
        XCTAssertEqual(try decoder.decode(VectorTextElement.self, from: bytes), original,
                       "Initializer defaults are legitimate saved values when explicitly encoded")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var recipe = try XCTUnwrap(json["recipe"] as? [String: Any])
        var font = try XCTUnwrap(recipe["font"] as? [String: Any])
        font["faceName"] = NSNull()
        font["packID"] = NSNull()
        recipe["font"] = font
        json["recipe"] = recipe
        json["motionGroupID"] = NSNull()
        json["animationGroupID"] = NSNull()
        XCTAssertEqual(try decoder.decode(VectorTextElement.self,
                                         from: JSONSerialization.data(withJSONObject: json)), original,
                       "Absent and explicit-null optional references both mean nil")
    }

    func testSavedFramesRejectEveryNonFourCornerCount() throws {
        let frame = TextFrame(origin: CGPoint(x: 8, y: 12), size: CGSize(width: 45, height: 30))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(frame))
                                        as? [String: Any])
        for count in [0, 1, 2, 3, 5] {
            var damaged = original
            damaged["corners"] = (0..<count).map { [$0, $0 + 1] }
            XCTAssertThrowsError(try decoder.decode(TextFrame.self,
                                                   from: JSONSerialization.data(withJSONObject: damaged)),
                                 "A \(count)-corner saved frame is damage, not an invented upright box")
        }
    }

    /// An unknown key is ignored, which is the other half of forward compatibility: today's build
    /// must open a document a *later* build wrote.
    func testAnUnrecognisedKeyIsIgnored() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(TextRecipe(string: "x")))
                                    as? [String: Any])
        json["outline"] = ["width": 4]
        let recipe = try decoder.decode(TextRecipe.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(recipe.string, "x")
    }

    // MARK: - Round trips

    func testAFullyPopulatedRecipeRoundTrips() throws {
        let original = TextRecipe(
            string: "The quick brown fox\njumped",
            font: FontDescriptor(familyName: "Helvetica", faceName: "Helvetica-BoldOblique",
                                 packID: nil, isBold: true, isItalic: true),
            typography: Typography(pointSize: 96, tracking: 3.5, lineHeightMultiple: 1.25,
                                   lineSpacing: 6, paragraphSpacing: 24, alignment: .justified),
            color: CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8),
            opacity: 0.5)
        let data = try encoder.encode(original)
        XCTAssertEqual(try decoder.decode(TextRecipe.self, from: data), original)
    }

    func testAFullyPopulatedElementRoundTrips() throws {
        let original = VectorTextElement(
            recipe: TextRecipe(string: "label"),
            frame: TextFrame(origin: CGPoint(x: 40, y: 90), size: CGSize(width: 300, height: 120),
                             autoSize: false),
            motionGroupID: UUID())
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(VectorTextElement.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, original.id, "Identity is persisted, not re-minted, when it is there.")
    }

    /// The `.projective` case exists in the enum from the first commit even though nothing writes it
    /// — so that a later `.mesh` is an additive case rather than a Codable migration (`ADD_TEXT.md`
    /// §1). It has to actually round-trip, or the claim is decoration.
    func testProjectiveModeRoundTripsEvenThoughNothingWritesItYet() throws {
        var frame = TextFrame(origin: .zero, size: CGSize(width: 10, height: 10))
        frame.mode = .projective
        let decoded = try decoder.decode(TextFrame.self, from: try encoder.encode(frame))
        XCTAssertEqual(decoded.mode, .projective)
    }

    // MARK: - Clamping

    /// A hand-edited or future-written document can carry anything, and `lineHeightMultiple = 0`
    /// lays every line on top of the last. The clamp is applied where typography is *read*, not in
    /// the setters, so a decoded value survives untouched and only the layout is defended.
    func testTypographyOutsideItsRangesIsClampedOnUseButNotOnDecode() throws {
        let bytes = try encoder.encode(Typography(pointSize: 100000, tracking: -9999, lineHeightMultiple: 0))
        let wild = try decoder.decode(Typography.self, from: bytes)
        XCTAssertEqual(wild.pointSize, 100000, "Decode preserves what the document said.")
        let clamped = wild.clamped
        XCTAssertEqual(clamped.pointSize, Typography.pointSizeRange.upperBound)
        XCTAssertEqual(clamped.lineHeightMultiple, Typography.lineHeightRange.lowerBound)
        XCTAssertEqual(clamped.tracking, Typography.trackingRange.lowerBound)
    }

    // MARK: - Geometry the frame owes its readers

    func testAnUprightFrameKnowsItIsATranslation() {
        let frame = TextFrame(origin: CGPoint(x: 12, y: 34), size: CGSize(width: 100, height: 50))
        XCTAssertTrue(frame.isUprightTranslation)
        XCTAssertEqual(frame.boundingBox, CGRect(x: 12, y: 34, width: 100, height: 50))
        XCTAssertEqual(frame[.topLeft], CGPoint(x: 12, y: 34))
        XCTAssertEqual(frame[.bottomRight], CGPoint(x: 112, y: 84))
    }

    func testARotatedFrameIsNotATranslationAndReportsItsBoundingBox() {
        // A 90°-rotated 100×50 box: the corners walk the same rectangle in a different order, which
        // is exactly the case a naive "are the corners a rectangle" test would wave through.
        var frame = TextFrame(origin: .zero, size: CGSize(width: 100, height: 50))
        frame.corners = [CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 100),
                         CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)]
        XCTAssertFalse(frame.isUprightTranslation)
        XCTAssertEqual(frame.boundingBox, CGRect(x: 0, y: 0, width: 50, height: 100))
    }

    func testMovingAFrameMovesItsCornersAndLeavesItsSizeAlone() {
        let frame = TextFrame(origin: CGPoint(x: 5, y: 5), size: CGSize(width: 40, height: 20))
        let moved = frame.moved(by: CGVector(dx: -3, dy: 7))
        XCTAssertEqual(moved.size, frame.size, "`size` is the domain; a move changes only the codomain.")
        XCTAssertEqual(moved[.topLeft], CGPoint(x: 2, y: 12))
        XCTAssertTrue(moved.isUprightTranslation)
    }

    func testResizingAFrameHoldsItsTopLeftStill() {
        let frame = TextFrame(origin: CGPoint(x: 9, y: 11), size: CGSize(width: 40, height: 20))
        let resized = frame.resized(to: CGSize(width: 200, height: 60))
        XCTAssertEqual(resized[.topLeft], CGPoint(x: 9, y: 11),
                       "Auto-size growth extends the box down and to the right — the point the "
                       + "artist tapped does not move out from under their text.")
        XCTAssertEqual(resized.boundingBox, CGRect(x: 9, y: 11, width: 200, height: 60))
    }

    // MARK: - styleOnly

    /// The live overlay uses this to tell "the artist typed" from "the artist changed the type".
    /// Getting it wrong means every keystroke rebuilds the text view's attributes and the caret
    /// jumps to the end of the line — which is a bug nothing headless would otherwise catch.
    func testStyleOnlyIgnoresTheStringAndNothingElse() {
        var a = TextRecipe(string: "one", typography: Typography(pointSize: 40))
        var b = a
        b.string = "two"
        XCTAssertEqual(a.styleOnly, b.styleOnly)
        b.typography.pointSize = 41
        XCTAssertNotEqual(a.styleOnly, b.styleOnly)
        a.color = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertNotEqual(a.styleOnly, TextRecipe(string: "one", typography: Typography(pointSize: 40)).styleOnly)
    }
}
