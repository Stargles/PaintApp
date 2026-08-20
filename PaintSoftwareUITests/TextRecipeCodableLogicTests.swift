import XCTest

/// `TextRecipe` and its neighbours as a persistence contract — `ADD_TEXT.md` §1, "Persistence: one
/// new case, no sidecar, no version number".
///
/// **The claim is one sentence: a blob missing every optional key decodes to defaults.** There is no
/// `formatVersion` anywhere in this project and this feature does not add one, so compatibility is
/// per-field `decodeIfPresent` and nothing else — which means every one of these types has to
/// hand-write `init(from:)`, because synthesized `Decodable` ignores property defaults and throws on
/// a missing key. `VectorStroke` already learned that (`VectorLayer.swift:29-31`); this file is what
/// stops it being re-learned.
///
/// It is written to fail on *omission*, in `ToolLogicTests`' spirit: adding a field to `Typography`
/// and forgetting its `decodeIfPresent` line makes `testAnEmptyObjectDecodesToEveryDefault` throw
/// rather than quietly ship a build that cannot open yesterday's document.
///
/// Headless, and reaching `TextObject.swift` through the project file's "App sources shared with
/// PaintSoftwareUITests" group — that file is Foundation and CoreGraphics only, which is exactly
/// what makes it reachable here.
final class TextRecipeCodableLogicTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - The whole claim

    /// `{}` — every key absent — is a valid recipe, and every field is its default.
    func testAnEmptyObjectDecodesToEveryDefault() throws {
        let recipe = try decode(TextRecipe.self, "{}")
        XCTAssertEqual(recipe, TextRecipe(),
                       "An empty JSON object must decode to a default `TextRecipe`. A field that "
                       + "throws or lands on a non-default value is a field whose `init(from:)` line "
                       + "is missing — which means a document written before that field existed no "
                       + "longer opens.")
    }

    func testAnEmptyTypographyDecodesToEveryDefault() throws {
        XCTAssertEqual(try decode(Typography.self, "{}"), Typography())
    }

    func testAnEmptyFontDescriptorDecodesToTheSystemFont() throws {
        let font = try decode(FontDescriptor.self, "{}")
        XCTAssertEqual(font, FontDescriptor.system)
        XCTAssertEqual(font.familyName, FontDescriptor.systemFamilyName)
        XCTAssertNil(font.faceName)
        XCTAssertNil(font.packID, "A descriptor with no pack is the system's, not a pack named \"\".")
    }

    func testAnEmptyFrameDecodesToADegenerateUprightBox() throws {
        let frame = try decode(TextFrame.self, "{}")
        XCTAssertEqual(frame.size, .zero)
        XCTAssertEqual(frame.corners.count, 4,
                       "A frame always carries four corners, even when the blob carried none — every "
                       + "reader indexes them by `Corner`.")
        XCTAssertEqual(frame.mode, .affine)
        XCTAssertTrue(frame.autoSize, "A frame nobody has resized is auto-sizing; that is what "
                      + "`autoSize` defaulting to true means.")
    }

    func testAnEmptyElementDecodesWithAFreshIdentity() throws {
        let a = try decode(VectorTextElement.self, "{}")
        let b = try decode(VectorTextElement.self, "{}")
        XCTAssertNotEqual(a.id, b.id,
                          "A missing `id` mints a fresh one. Defaulting to a *constant* UUID would "
                          + "make two malformed elements the same element, and the display list is "
                          + "keyed by identity.")
        XCTAssertNil(a.motionGroupID)
    }

    // MARK: - Partial blobs

    /// The realistic version of the claim: a document written by an older build carries the fields
    /// that existed then and none of the ones added since.
    func testAPartialTypographyKeepsWhatItStatesAndDefaultsTheRest() throws {
        let typography = try decode(Typography.self, #"{"pointSize": 120, "alignment": "right"}"#)
        XCTAssertEqual(typography.pointSize, 120)
        XCTAssertEqual(typography.alignment, .right)
        XCTAssertEqual(typography.tracking, 0)
        XCTAssertEqual(typography.lineHeightMultiple, 1)
        XCTAssertEqual(typography.lineSpacing, 0)
        XCTAssertEqual(typography.paragraphSpacing, 0)
    }

    func testAPartialRecipeKeepsItsStringAndDefaultsItsType() throws {
        let recipe = try decode(TextRecipe.self, #"{"string": "hello"}"#)
        XCTAssertEqual(recipe.string, "hello")
        XCTAssertEqual(recipe.typography, Typography())
        XCTAssertEqual(recipe.font, .system)
        XCTAssertEqual(recipe.opacity, 1)
    }

    /// A frame whose `corners` array is the wrong length is repaired to an upright box of the stated
    /// size rather than thrown out. `TextFrame.init(from:)` argues why: the rotation is a bug in
    /// whatever wrote it, and the words are the half worth keeping.
    func testAFrameWithTheWrongNumberOfCornersIsRepairedRatherThanRejected() throws {
        let frame = try decode(TextFrame.self, #"{"size": [200, 80], "corners": [[10, 10], [210, 10]]}"#)
        XCTAssertEqual(frame.size, CGSize(width: 200, height: 80))
        XCTAssertEqual(frame.corners, TextFrame.uprightCorners(origin: .zero,
                                                               size: CGSize(width: 200, height: 80)))
    }

    /// An unknown key is ignored, which is the other half of forward compatibility: today's build
    /// must open a document a *later* build wrote.
    func testAnUnrecognisedKeyIsIgnored() throws {
        let recipe = try decode(TextRecipe.self, #"{"string": "x", "outline": {"width": 4}}"#)
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
        let wild = try decode(Typography.self,
                              #"{"pointSize": 100000, "lineHeightMultiple": 0, "tracking": -9999}"#)
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
