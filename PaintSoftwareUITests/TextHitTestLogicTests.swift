import UIKit
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

    // MARK: - Scribble, which is a hit test iOS runs and we do not
    //
    // The other question of "who owns this touch", asked one layer above the app. `ADD_TEXT.md`:208
    // left it open — *"whether iOS's own Scribble recognizer fights the canvas's"* — and the answer
    // arrived as a bug report: a pencil tap spawned the box with no keyboard, because iPadOS reads a
    // pencil over an editable text input as handwriting and offers Scribble in the keyboard's place.
    // `TextOverlayView.scribbleInteraction(_:shouldBeginAt:)` refuses.
    //
    // **What these three can and cannot prove.** They prove the veto is installed on the right view,
    // that it is the overlay answering, and that the answer is `false` for every location including
    // the ones a "suppress it only over there" regression would let through. They cannot prove iOS
    // *asks* — that needs a pencil, and XCUITest cannot synthesise one at all (see
    // `tools/recording2xcuitest.py`, which refuses to downgrade one to a finger for this reason). The
    // on-device half is the `scribble.veto` line the delegate writes into an `ActionRecorder` file.

    private func overlay() -> TextOverlayView {
        TextOverlayView(frame: CGRect(origin: .zero, size: TextHitTestLogicTests.canvasSize))
    }

    private func installedScribbleInteraction(on overlay: TextOverlayView) throws -> UIScribbleInteraction {
        let found = overlay.textView.interactions.compactMap { $0 as? UIScribbleInteraction }
        XCTAssertEqual(found.count, 1, "One veto, on the editor's own text view.")
        return try XCTUnwrap(found.first)
    }

    /// The wiring. `UIScribbleInteraction` holds its delegate weakly and the text view holds the
    /// interaction, so a version of this that forgot to keep the overlay alive would leave a live
    /// interaction with a nil delegate — which defaults to *allowing* Scribble, silently.
    ///
    /// **`interaction.view` is the assertion that UIKit accepted it**, rather than that we appended
    /// an object to an array: `view` is set by `UIInteraction.willMove(to:)`/`didMove(to:)`, which
    /// only UIKit calls. The count is `1` and not `2` for a second reason worth stating — iOS's own
    /// handwriting support is *not* exposed as a `UIScribbleInteraction` on the text view, which is
    /// why the fix had to add one rather than find and remove one.
    func testTheEditorsTextViewCarriesAScribbleVeto() throws {
        let view = overlay()
        let interaction = try installedScribbleInteraction(on: view)
        XCTAssertTrue(interaction.delegate === view,
                      "A nil delegate is not a veto: the callback is optional and defaults to YES.")
        XCTAssertTrue(interaction.view === view.textView,
                      "UIKit never adopted the interaction, so it will never ask it anything.")
    }

    /// Every location, not one. The delegate is handed a point and nothing else — no touch, no
    /// stroke — so there is no seam on which "a tap keyboards, a scrawl writes" could be built, and a
    /// location-conditional answer would only make the bug intermittent.
    func testScribbleIsRefusedAnywhereInsideTheBoxAndOutIt() throws {
        let view = overlay()
        let interaction = try installedScribbleInteraction(on: view)
        let probes = [CGPoint.zero,
                      CGPoint(x: 1, y: 1),
                      CGPoint(x: 60, y: 20),
                      CGPoint(x: 100, y: 100),
                      CGPoint(x: -40, y: -40),
                      CGPoint(x: 10_000, y: 10_000)]
        for point in probes {
            XCTAssertFalse(view.scribbleInteraction(interaction, shouldBeginAt: point),
                           "Scribble allowed at \(point) — the pencil is the brush here.")
        }
    }

    /// And it still refuses once a session is live, which is the only state the artist ever sees it
    /// in. `update(isActive:…)` is the whole of the view's public surface and re-runs a good deal of
    /// setup; the veto is installed once in `init` and must not be a casualty of that.
    func testTheVetoSurvivesAnActiveEditingSession() throws {
        let view = overlay()
        view.update(isActive: true,
                    frame: TextFrame(origin: CGPoint(x: 20, y: 20),
                                     size: CGSize(width: 120, height: 40)),
                    recipe: recipe("Label"),
                    canvasScale: 1)
        let interaction = try installedScribbleInteraction(on: view)
        XCTAssertTrue(interaction.delegate === view)
        XCTAssertFalse(view.scribbleInteraction(interaction, shouldBeginAt: CGPoint(x: 60, y: 30)))
    }
}
