import XCTest
import UIKit

/// **BUGS.md's 2026-09-04 defect, run rather than reasoned about** — *"Starting a stroke before the
/// last one has rendered leaves the last one off screen"*.
///
/// That entry opens by saying the defect is *"confirmed by tracing every path that repaints the
/// base, not measured"*, because `StrokeCanvasView` is not in this target and the sequence is too
/// fast to catch by hand. `UnlandedInk` is the decision lifted out of the view for exactly that
/// reason, and this is the sequence the entry describes, step by step.
///
/// **What each test's two operands are** is written on it, because the failure shapes CLAUDE.md
/// records are all failures of the operands rather than of the arithmetic. The one that applies here
/// most is *"an assertion true at the wrong level"*: the thing worth pinning is not that an array
/// appends, it is that **the picture is still on screen at the step the old code dropped it**, so
/// every assertion below is taken at a named step of the artist's sequence rather than after it.
final class UnlandedInkLogicTests: XCTestCase {

    // MARK: - The defect

    /// **The whole defect, as five steps.** Stroke *n* is finished and its render is in flight;
    /// stroke *n+1* begins, is drawn, and finishes, all before that render lands.
    ///
    /// The operands are *"is stroke n's picture among the pictures on screen"* at step 3 — the step
    /// where the shipped code released `scratchIsHeldForRerender` because a new `scratch` had been
    /// assigned — against *"it is"*. Deleting `hold`'s append, or restoring the old release, empties
    /// it and this goes red.
    func testAStrokeStartedBeforeTheLastOneRenderedLeavesBothOnScreen() {
        var ink = UnlandedInk()

        // 1. Stroke n commits at version 7. Its render is dispatched and has not landed.
        ink.hold(Self.paint(id: 1, version: 7))
        XCTAssertEqual(ink.pictures.map(\.id), [1],
                       "step 1: the stroke that has just been committed is on screen as held ink, "
                       + "because the base slot still holds the render that predates it")

        // 2. Stroke n+1 begins. The view mints a *new* live scratch here, which is the event the
        //    shipped code turned into "release the previous stroke". `UnlandedInk` is not told about
        //    it at all — a live scratch is not its business — so nothing may move.
        XCTAssertEqual(ink.pictures.map(\.id), [1],
                       "step 2: beginning the next stroke must not move held ink. This is the step "
                       + "BUGS.md names: the shipped code released the hold in `scratch`'s didSet, "
                       + "so stroke n was in neither the base nor the overlay")

        // 3. Stroke n+1 commits at version 8, before the render of 7 has landed.
        ink.hold(Self.paint(id: 2, version: 8))
        XCTAssertEqual(ink.pictures.map(\.id), [1, 2],
                       "step 3: two finished strokes, neither of them in the base, are both on screen")

        // 4. The render of version 7 lands. It contains stroke n and not stroke n+1.
        ink.retire(upTo: 7)
        XCTAssertEqual(ink.pictures.map(\.id), [2],
                       "step 4: the base now contains stroke n, so holding its picture as well would "
                       + "draw it twice — and stroke n+1 is still the base's alone to lack")

        // 5. The render of version 8 lands.
        ink.retire(upTo: 8)
        XCTAssertTrue(ink.isEmpty,
                      "step 5: a base that contains every stroke leaves nothing for the overlay to say")
    }

    /// **A later render is a superset, so one landing can retire several.** Renders are dispatched
    /// one per commit onto a single serial queue, and a fast artist finishes two strokes inside one
    /// of them — so the base that finally lands is a picture of both.
    ///
    /// Operands: the held set after `retire(upTo: 9)` against empty. It would go red on `==` instead
    /// of `<=`, which is the one-character mistake this pins.
    func testABaseThatArrivesLateRetiresEveryStrokeItContains() {
        var ink = UnlandedInk()
        ink.hold(Self.paint(id: 1, version: 7))
        ink.hold(Self.paint(id: 2, version: 8))
        ink.hold(Self.paint(id: 3, version: 9))
        ink.retire(upTo: 9)
        XCTAssertTrue(ink.isEmpty,
                      "a render of version 9 walked a display list containing all three strokes, so "
                      + "all three are in the base it installed")
    }

    /// **A base older than the ink does not retire it**, which is the other half of the same
    /// comparison and the half that would show as ink vanishing rather than as ink doubled.
    ///
    /// Reachable in the shipped app: `DeferredVectorRender.step` can install a *memoized* render
    /// (`.showNow`) for a version the canvas has since moved past, and `beginVectorFloat` renders
    /// synchronously at whatever version it finds.
    func testABaseOlderThanTheHeldInkRetiresNothing() {
        var ink = UnlandedInk()
        ink.hold(Self.paint(id: 1, version: 12))
        ink.retire(upTo: 11)
        XCTAssertEqual(ink.pictures.map(\.id), [1],
                       "a base rasterized before this stroke existed cannot contain it")
    }

    // MARK: - What reaches the screen

    /// **Commit order is z-order, and it is the order the base will draw them in.**
    /// `VectorCanvas.renderLocalContent` walks the display list in order and appends put a new
    /// stroke at the end, so a held set that composited in any other order would swap over at the
    /// moment the base landed.
    ///
    /// Operands: the ids in `pictures` against the order they were held in. It could go red — an
    /// implementation that inserted at the head, or sorted by version descending, or de-duplicated
    /// by window, would fail it.
    func testHeldPicturesStayInCommitOrder() {
        var ink = UnlandedInk()
        ink.hold(Self.paint(id: 5, version: 1))
        ink.hold(Self.paint(id: 6, version: 2))
        ink.hold(Self.paint(id: 7, version: 3))
        XCTAssertEqual(ink.pictures.map(\.id), [5, 6, 7],
                       "the screen stacks finished strokes in the order they were made, which is the "
                       + "order the display list will draw them in when the base replaces them")
    }

    /// **Every picture keeps its own alpha, and that is why they are separate layers rather than one
    /// accumulating surface.** BRUSH.md §2.11 caps a stroke at its own opacity once; two strokes at
    /// different opacities merged into one window and shown at one alpha is a different number from
    /// either of them, and the artist would watch both change shade when the base landed.
    ///
    /// Operands: the two alphas carried out of `pictures` against the two that went in.
    func testTwoStrokesAtDifferentOpacitiesKeepTheirOwnAlphas() {
        var ink = UnlandedInk()
        ink.hold(Self.paint(id: 1, version: 1, alpha: 0.25))
        ink.hold(Self.paint(id: 2, version: 2, alpha: 1))
        XCTAssertEqual(ink.pictures.map(\.alpha), [0.25, 1],
                       "a held picture is shown at the opacity its own stroke will merge at — the "
                       + "single overlay this replaced could carry only one of the two")
    }

    /// **The base hole is the removal's window, and there is at most one of them.** See
    /// `UnlandedInk.hold`: two removals need two holes, `setBaseHole` builds one even-odd path, and
    /// two overlapping rectangles in an even-odd path cancel back to opaque.
    ///
    /// Operands: `baseHole` after two erasers against the *second* one's rect. Red if `hold` kept
    /// both (the hole would be the first's) or dropped the incoming one.
    func testASecondRemovalReplacesTheFirstRatherThanAddingASecondHole() {
        var ink = UnlandedInk()
        let first = CGRect(x: 10, y: 10, width: 40, height: 40)
        let second = CGRect(x: 200, y: 200, width: 30, height: 30)
        ink.hold(Self.erase(id: 1, version: 1, window: first))
        XCTAssertEqual(ink.baseHole, first, "one removal punches its own window out of the base")
        ink.hold(Self.erase(id: 2, version: 2, window: second))
        XCTAssertEqual(ink.pictures.map(\.id), [2],
                       "the older removal goes rather than leaving a hole nothing draws into")
        XCTAssertEqual(ink.baseHole, second, "the hole follows the removal that is on screen")
    }

    /// **An additive picture is kept whatever is below it, including a removal**, and the composite
    /// is right without any rule at all: base (punched under the removal) + the removal's own window
    /// + the ink drawn after it. That is the same order and the same operations the display list
    /// runs when the render lands.
    ///
    /// Operands: the ids and the hole after erase-then-paint. Red if `hold` dropped everything below
    /// an additive picture, or if `baseHole` read the newest picture rather than the removal.
    func testPaintingAfterAnEraseKeepsBothAndKeepsTheHole() {
        var ink = UnlandedInk()
        let window = CGRect(x: 10, y: 10, width: 40, height: 40)
        ink.hold(Self.erase(id: 1, version: 1, window: window))
        ink.hold(Self.paint(id: 2, version: 2))
        XCTAssertEqual(ink.pictures.map(\.id), [1, 2],
                       "the erase stands in for the base inside its window and the later stroke's "
                       + "ink goes over it, which is what drawing after erasing means")
        XCTAssertEqual(ink.baseHole, window,
                       "the removal still needs the base punched out under it — the ink drawn "
                       + "afterwards does not put the erased pixels back")
    }

    /// **Nothing held survives a canvas the pictures are not about.** Two cels' `version` counters
    /// are independent and can be equal by coincidence, so a picture kept across a layer, cel or
    /// frame change would be drawn over the new cel's base and retired by an unrelated number.
    func testNothingSurvivesTheCanvasChanging() {
        var ink = UnlandedInk()
        ink.hold(Self.paint(id: 1, version: 3))
        ink.hold(Self.paint(id: 2, version: 4))
        ink.removeAll()
        XCTAssertTrue(ink.isEmpty, "held ink belongs to the canvas it was drawn on")
        XCTAssertNil(ink.baseHole, "and so does the hole it asked for")
    }

    // MARK: - Fixtures

    /// A real 1×1 image rather than a placeholder: the field is what the view hands to a layer's
    /// `contents`, and a type that would accept nil there is a type a caller can hold nothing in.
    private static let pixel: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()

    private static func paint(id: Int, version: Int, alpha: CGFloat = 1) -> UnlandedInk.Picture {
        UnlandedInk.Picture(id: id, version: version,
                            windowRect: CGRect(x: 0, y: 0, width: 64, height: 64),
                            alpha: alpha, replacesBase: false, image: pixel)
    }

    private static func erase(id: Int, version: Int, window: CGRect) -> UnlandedInk.Picture {
        UnlandedInk.Picture(id: id, version: version, windowRect: window,
                            alpha: 1, replacesBase: true, image: pixel)
    }
}
