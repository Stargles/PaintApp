import XCTest

/// Pure-logic tests for `VectorCanvas.topmostText(atCanvasPoint:)` — the query that makes a text
/// object on a vector layer *re-openable*, and for `TextMeasure.inkBounds`, the measure-only bounds
/// the display list's geometry asks for.
///
/// **The interesting assertion is the rotated box**, and it is the one that tells the shipped test
/// apart from an easy one. A hit test written against `TextFrame.boundingBox` passes every upright
/// case and then claims the empty corners of a rotated box — tap well outside the words, on blank
/// canvas, and the label opens for editing. So the pair here is: a point inside a rotated box hits,
/// and a point in the axis-aligned corner *outside* it misses. `ADD_TEXT.md` stage 3 names exactly
/// that pair.
///
/// The predicate under test is containment in the frame's quad, which is the box tested through
/// `H⁻¹` written without the matrix — a homography maps the layout box onto the quad and takes
/// straight lines to straight lines, so the two statements are one. That is what lets stage 3 answer
/// it exactly, a stage before `Homography` exists.
///
/// Lives in `PaintSoftwareUITests` with the other `*LogicTests`; `Engine/VectorLayer.swift`,
/// `Engine/TextObject.swift` and `Engine/TextLayout.swift` are compiled into this target directly.
final class TextHitTestLogicTests: XCTestCase {

    private static let canvasSize = CGSize(width: 200, height: 200)

    // MARK: - Fixtures

    private static func testBrush() -> Brush {
        Brush(name: "Test", shape: .hardRound, size: 10, opacity: 1, flow: 1,
              spacingFraction: 0.1, hardness: 1, stabilization: 0, scatter: 0,
              rotationJitter: 0, dynamics: .fixed, grain: .disabled, blendMode: .normal)
    }

    private func stroke() -> VectorStroke {
        VectorStroke(brush: Self.testBrush(),
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 10, opacity: 1,
                     samples: [VectorSample(x: 10, y: 10, pressure: 1),
                               VectorSample(x: 60, y: 60, pressure: 1)])
    }

    private func recipe(_ string: String = "Label", pointSize: CGFloat = 24) -> TextRecipe {
        TextRecipe(string: string, font: .system, typography: Typography(pointSize: pointSize))
    }

    private func upright(_ string: String = "Label",
                         origin: CGPoint = CGPoint(x: 40, y: 40),
                         size: CGSize = CGSize(width: 80, height: 40),
                         autoSize: Bool = true) -> VectorTextElement {
        VectorTextElement(recipe: recipe(string),
                          frame: TextFrame(origin: origin, size: size, autoSize: autoSize))
    }

    /// A 100×40 box turned 45° about its own centre `(100, 100)`.
    ///
    /// Its axis-aligned bounding box runs roughly `(50.5, 50.5)…(149.5, 149.5)`, while the quad
    /// itself is a diamond inside that square — so the square's corners are the region the two
    /// answers disagree about, and `(60, 60)` sits squarely in one of them.
    private func rotated45() -> VectorTextElement {
        let centre = CGPoint(x: 100, y: 100)
        let size = CGSize(width: 100, height: 40)
        let k = CGFloat(2).squareRoot() / 2                     // cos 45° = sin 45°
        let corners = TextFrame.uprightCorners(origin: CGPoint(x: centre.x - size.width / 2,
                                                               y: centre.y - size.height / 2),
                                               size: size)
            .map { corner -> CGPoint in
                let dx = corner.x - centre.x, dy = corner.y - centre.y
                return CGPoint(x: centre.x + dx * k - dy * k, y: centre.y + dx * k + dy * k)
            }
        return VectorTextElement(recipe: recipe(),
                                 frame: TextFrame(size: size, corners: corners, mode: .affine,
                                                  autoSize: false))
    }

    private func canvas(_ elements: [VectorElement],
                        transform: CGAffineTransform = .identity) -> VectorCanvas {
        VectorCanvas(size: Self.canvasSize, elements: elements, transform: transform)
    }

    // MARK: - The rotated box, which is the whole point

    func testAPointInsideARotatedBoxHits() {
        let element = rotated45()
        let hit = canvas([.text(element)]).topmostText(atCanvasPoint: CGPoint(x: 100, y: 100), slop: 0)
        XCTAssertEqual(hit?.id, element.id, "The box's own centre is inside it at any rotation.")

        // A point off-centre along the box's long axis — still inside the quad, and outside where an
        // unrotated box of the same `size` would be.
        let alongAxis = canvas([.text(element)]).topmostText(atCanvasPoint: CGPoint(x: 125, y: 125),
                                                             slop: 0)
        XCTAssertEqual(alongAxis?.id, element.id)
    }

    func testAPointInTheCornerOutsideARotatedBoxMisses() {
        let element = rotated45()
        let corner = CGPoint(x: 60, y: 60)

        // Stated rather than assumed: the point really is inside the bounding rectangle, so this
        // test fails loudly the day somebody swaps the quad test for a `boundingBox.contains`.
        XCTAssertTrue(element.frame.boundingBox.contains(corner),
                      "Fixture check — the corner must lie inside the AABB for the test to mean anything.")
        XCTAssertNil(canvas([.text(element)]).topmostText(atCanvasPoint: corner, slop: 0),
                     "Tapping blank canvas in the corner of a rotated box's bounding rectangle is not tapping the text.")
    }

    // MARK: - Upright boxes, ordering, slop

    func testAnUprightBoxHitsInsideAndMissesOutside() {
        let element = upright()
        let subject = canvas([.text(element)])
        XCTAssertEqual(subject.topmostText(atCanvasPoint: CGPoint(x: 60, y: 60), slop: 0)?.id, element.id)
        XCTAssertNil(subject.topmostText(atCanvasPoint: CGPoint(x: 150, y: 150), slop: 0))
    }

    /// The box is hit, not the glyphs. Tapping the gap under a single line of type — inside the box,
    /// nowhere near a letterform — is tapping the text, and an artist aims at the word rather than at
    /// the stem of a "l".
    func testTheBoxIsHitRatherThanTheGlyphs() {
        let element = upright("i", origin: CGPoint(x: 40, y: 40), size: CGSize(width: 80, height: 40))
        let hit = canvas([.text(element)]).topmostText(atCanvasPoint: CGPoint(x: 115, y: 75), slop: 0)
        XCTAssertEqual(hit?.id, element.id)
    }

    func testTheTopmostOverlappingObjectWins() {
        let below = upright("below")
        let above = upright("above")
        let subject = canvas([.text(below), .stroke(stroke()), .text(above)])
        XCTAssertEqual(subject.topmostText(atCanvasPoint: CGPoint(x: 60, y: 60))?.id, above.id,
                       "Later in the display list is nearer the artist.")
    }

    /// `slop` is a fingertip's worth of reach measured to the quad's *edges*, so a rotated box is no
    /// harder to hit than an upright one — the same reason `topmostStroke` adds slop to a hairline.
    func testSlopReachesJustOutsideTheEdge() {
        let element = upright(origin: CGPoint(x: 40, y: 40), size: CGSize(width: 80, height: 40))
        let justOutside = CGPoint(x: 124, y: 60)                 // 4 pt past the right edge
        let subject = canvas([.text(element)])
        XCTAssertNil(subject.topmostText(atCanvasPoint: justOutside, slop: 0))
        XCTAssertEqual(subject.topmostText(atCanvasPoint: justOutside, slop: 6)?.id, element.id)
    }

    func testACanvasWithNoTextAnswersNil() {
        XCTAssertNil(canvas([.stroke(stroke())]).topmostText(atCanvasPoint: CGPoint(x: 30, y: 30)))
    }

    func testADegenerateFrameIsNeverHit() {
        let element = VectorTextElement(recipe: recipe(),
                                        frame: TextFrame(origin: CGPoint(x: 50, y: 50), size: .zero))
        XCTAssertNil(canvas([.text(element)]).topmostText(atCanvasPoint: CGPoint(x: 50, y: 50), slop: 0),
                     "A zero-area quad has no inside; only the slop collar may reach it.")
    }

    /// The tap arrives in canvas space and the frame is stored in the layer's local space, so the
    /// layer's own transform has to come off the point first. Without it, tapping a moved layer's
    /// label opens nothing and the artist gets a second box on top of the first.
    func testTheLayersOwnTransformIsTakenOffTheTap() {
        let element = upright(origin: CGPoint(x: 40, y: 40), size: CGSize(width: 80, height: 40))
        let moved = canvas([.text(element)], transform: CGAffineTransform(translationX: 60, y: 20))
        XCTAssertEqual(moved.topmostText(atCanvasPoint: CGPoint(x: 120, y: 80), slop: 0)?.id, element.id,
                       "The object renders 60 right and 20 down of where it is stored; the tap must follow.")
        XCTAssertNil(moved.topmostText(atCanvasPoint: CGPoint(x: 60, y: 60), slop: 0),
                     "Where it *used* to be is now blank canvas.")
    }

    // MARK: - `TextMeasure.inkBounds`
    //
    // Identities rather than measured widths, for `TextLayoutLogicTests`' stated reason: "this string
    // is 412.5 points wide" is a claim about a font file Apple revises, not about this code.

    func testInkBoundsIsInsideTheFrameAndNotEmpty() throws {
        let element = upright("Some words", origin: CGPoint(x: 40, y: 40),
                              size: CGSize(width: 160, height: 60))
        let ink = try XCTUnwrap(TextMeasure.inkBounds(of: element))
        XCTAssertGreaterThan(ink.width, 0)
        XCTAssertGreaterThan(ink.height, 0)
        XCTAssertGreaterThanOrEqual(ink.minX, element.frame.boundingBox.minX - 1)
        XCTAssertGreaterThanOrEqual(ink.minY, element.frame.boundingBox.minY - 1)
    }

    func testAnEmptyOrBlankObjectHasNoInk() {
        XCTAssertNil(TextMeasure.inkBounds(of: upright("")),
                     "An empty object is not a backdrop; a punch kept alive by one is a hole in nothing.")
        XCTAssertNil(TextMeasure.inkBounds(of: upright("   \n  ")))
    }

    /// A box the artist sized clips (`ADD_TEXT.md` §5.3), so ink past its edge is not on the canvas
    /// and must not be claimed as content. A pristine box was grown to fit and has nothing to clip.
    func testASizedBoxNeverReportsInkOutsideItself() throws {
        let long = String(repeating: "wide ", count: 40)
        let sized = VectorTextElement(recipe: recipe(long, pointSize: 40),
                                      frame: TextFrame(origin: CGPoint(x: 20, y: 20),
                                                       size: CGSize(width: 60, height: 30),
                                                       autoSize: false))
        let ink = try XCTUnwrap(TextMeasure.inkBounds(of: sized))
        let box = sized.frame.boundingBox
        XCTAssertLessThanOrEqual(ink.maxX, box.maxX + 0.5)
        XCTAssertLessThanOrEqual(ink.maxY, box.maxY + 0.5)
    }

    /// The stated fallback: a frame that is not an upright translation measures its line boxes in
    /// box-local space, and mapping those through the frame's map is stage 5's homography. Larger is
    /// the safe direction, so it reports the whole bounding box rather than guessing.
    func testARotatedFrameFallsBackToItsBoundingBox() throws {
        let element = rotated45()
        let ink = try XCTUnwrap(TextMeasure.inkBounds(of: element))
        XCTAssertEqual(ink, element.frame.boundingBox)
    }
}
