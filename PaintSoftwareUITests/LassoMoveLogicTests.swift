import XCTest
import SwiftUI
import UIKit

/// **A lasso move moves only what is inside the loop.**
///
/// The failure mode this file exists for is not a crash. It is *silent artwork loss*: a suppression
/// that is never cleared leaves elements in the saved document that count towards every memory bound
/// and render nowhere, so the artist sees a hole they cannot fill, cannot undo, and gets back only on
/// relaunch. Nothing about that produces a warning or a red test unless a test enumerates the
/// teardown paths and asserts on both halves — which is what
/// `testEveryTeardownPathLeavesNothingSuppressedAndNothingDropped` does, and why it is first.
///
/// Pure logic, no simulator: `beginVectorLassoMove` / `nudgeVectorFloat` /
/// `commitVectorFloatIfNeeded` are the seams the toolbar and the transform overlay drive, and
/// driving them directly is the same sequence of calls a real gesture produces.
final class LassoMoveLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let size = CanvasFixture.canvasSize   // 64 × 64

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

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

    private func stroke(from a: CGPoint, to b: CGPoint, size: CGFloat = 4,
                        composite: StrokeComposite = .paint,
                        brush: Brush = BrushLibrary.hardRound) -> VectorStroke {
        VectorStroke(id: UUID(), brush: brush, color: black(), size: size, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)],
                     composite: composite)
    }

    /// A closed rectangular loop, in canvas space — what `SelectionOverlayView` hands `finishSelection`
    /// for a rectangle drag, and the shape every containment question here is asked with.
    private func loop(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ path: CGPath) {
        manager.selection = Selection(path: path, bounds: path.boundingBoxOfPath,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    private func cgImage(_ vector: VectorCanvas) -> CGImage? { vector.render().cgImage }

    /// `a·d − b·c`. Its **sign** is the whole question a mirror asks: negative is a plane turned over,
    /// positive is a plane merely turned. `CGAffineTransform` has no such accessor of its own.
    private func determinant(_ t: CGAffineTransform) -> CGFloat { t.a * t.d - t.b * t.c }

    /// The recipe laid out into a box of `boxWidth` — line count, line ranges and line widths, with
    /// the font resolved the way the app resolves it. What "did the text re-flow" is actually asked
    /// of; the corners cannot answer it.
    private func layout(of recipe: TextRecipe, boxWidth: CGFloat) -> TextLayout.Metrics {
        TextLayout.measure(recipe, font: TextLayout.resolvedFont(for: recipe).font, maxWidth: boxWidth)
    }

    /// The opaque bounding box of what a canvas actually draws — the question "did the *ink* move",
    /// which is not the same question as "did the samples move". See
    /// `testANudgeMovesTheRenderedInkAndNotOnlyTheSamples`.
    private func inkBounds(_ vector: VectorCanvas) -> CGRect? {
        PixelOps.opaqueContentBounds(vector.render())
    }

    // MARK: - The one that would silently lose artwork

    /// Which of the two lifts a test is driving. **Both reach the same float**, which is the whole
    /// point of `beginVectorWholeCelMove` — so every teardown door has to be walked twice, once with
    /// a subset of the cel suppressed and once with all of it.
    private enum LiftKind: String, CaseIterable {
        case lasso = "lasso"
        case wholeCel = "whole cel"
    }

    /// The lift a door test is opened with. The lasso arm draws the loop the rest of this file uses.
    @discardableResult
    private func lift(_ kind: LiftKind, _ manager: CanvasManager, _ layerIndex: Int) -> Bool {
        switch kind {
        case .lasso:
            select(manager, layerIndex, loop(CGRect(x: 24, y: 4, width: 32, height: 56)))
            return manager.beginVectorLassoMove()
        case .wholeCel:
            return manager.beginVectorWholeCelMove()
        }
    }

    /// **Every way a float can end leaves nothing suppressed and nothing dropped — for both lifts.**
    ///
    /// Ten paths, and each is a different door: the artist taps Move again; they undo before nudging;
    /// they switch tool or panel; they change layer; they change frame; they press undo after a
    /// nudge; they **Rasterize** the layer; they **Merge Down**. A leak on any one of them is artwork
    /// that is in the document and renders nowhere.
    ///
    /// Watched failing with `commitVectorFloatIfNeeded`'s `suppressedElementIDs = []` removed — four
    /// of the six original doors went red at once: *commit: 2 element(s) still suppressed after
    /// commit*, and the same for tool switch, layer change and frame change.
    ///
    /// **Rasterize and Merge Down were added with `beginVectorWholeCelMove` (2026-08-27), and they
    /// are worse than a leak.** `rasterizeLayer` never settled the float, and the flatten it performs
    /// goes through `cel.vector?.render(quality:)` — which *honours* the suppression — before setting
    /// `vector = nil`. With a lasso float that bakes away the lassoed subset; with a whole-cel float,
    /// where every id is suppressed, it bakes the entire cel to blank, in the saved document, and the
    /// geometry that could have restored it is gone in the same statement. Merge Down reaches the
    /// identical code through `mergeLayers`. `ink` below is what catches it: a teardown that leaked
    /// leaves the flattened raster missing exactly the elements that were floating.
    ///
    /// Watched failing with `rasterizeLayer`'s `commitVectorFloatIfLifted` removed — and the two
    /// lifts fail differently, which is the amplification stated as output:
    /// *lasso / rasterize: the flatten lost ink on the right* — `("26.0") is not equal to ("58.0")`,
    /// the lassoed half gone — against
    /// *whole cel / rasterize: the flatten is blank — the whole cel was baked away*.
    /// Merge Down went red on the same run for the same reason.
    func testEveryTeardownPathLeavesNothingSuppressedAndNothingDropped() {
        /// The flattened image of the layer's first cel — what Rasterize and Merge Down actually
        /// wrote. Nil when the flatten is blank, which is the whole-cel failure.
        func flattenedInk(_ manager: CanvasManager, _ layerIndex: Int) -> CGRect? {
            guard manager.layers.indices.contains(layerIndex),
                  let cel = manager.layers[layerIndex].cels.first else { return nil }
            return PixelOps.opaqueContentBounds(
                PixelOps.rasterize(cel: cel, canvasSize: CanvasFixture.canvasSize))
        }

        let paths: [(name: String, act: (CanvasManager, Int) -> Void,
                     ink: ((CanvasManager, Int) -> CGRect?)?)] = [
            ("commit", { manager, _ in manager.commitVectorFloatIfNeeded() }, nil),
            ("cancel", { manager, _ in manager.cancelVectorFloat() }, nil),
            ("tool switch", { manager, _ in manager.commitAllInteractiveState() }, nil),
            ("layer change", { manager, _ in manager.currentLayerIndex = 0 }, nil),
            ("frame change", { manager, _ in
                // Onto a frame the *other* cel covers. A same-cel frame tick is deliberately not a
                // context change (`handleActiveContextChanged`), so scrubbing inside one cel's range
                // leaves the float alone — the raster piece behaves identically.
                let layerIndex = manager.currentLayerIndex
                manager.layers[layerIndex].cels[0].frameCount = 4
                manager.layers[layerIndex].cels.append(
                    Cel(id: UUID(), startFrame: 4, frameCount: 8,
                        raster: .empty(size: CanvasFixture.canvasSize),
                        vector: .empty(size: CanvasFixture.canvasSize)))
                manager.currentFrame = 6
            }, nil),
            ("undo with zero nudges", { manager, _ in manager.undo() }, nil),
            // The two handle kinds the box gained in stage 1. A scale and a rotate reach the same
            // teardown as a move, and this is the artwork-loss test, so they belong in it.
            ("commit after a scale", { manager, _ in
                manager.nudgeVectorFloat(to: {
                    guard var t = manager.vectorFloat?.frame.transform else { return .identity }
                    t.scale *= 1.8
                    return t
                }())
                manager.commitVectorFloatIfNeeded()
            }, nil),
            ("undo after a rotate", { manager, _ in
                manager.nudgeVectorFloat(to: {
                    guard var t = manager.vectorFloat?.frame.transform else { return .identity }
                    t.rotation += 0.5
                    return t
                }())
                manager.undo()
            }, nil),
            // The two that flatten. Both must leave the ink where it was: the float is settled, not
            // baked away, and no drag happened, so the picture is the one that was there before.
            ("rasterize", { manager, layerIndex in
                manager.rasterizeLayer(layerIndex: layerIndex)
            }, { manager, layerIndex in flattenedInk(manager, layerIndex) }),
            ("merge down", { manager, layerIndex in
                manager.mergeLayers(manager.layers[layerIndex].id, manager.layers[layerIndex - 1].id)
            }, { manager, _ in flattenedInk(manager, 0) })
        ]
        for kind in LiftKind.allCases {
            for path in paths {
                let label = "\(kind.rawValue) / \(path.name)"
                let (manager, layerIndex, vector) = fixture()
                vector.addStroke(stroke(from: CGPoint(x: 8, y: 20), to: CGPoint(x: 56, y: 20)))
                vector.addStroke(stroke(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 30, y: 44)))
                let idsBefore = Set(vector.elements.map(\.id))
                // Taken before the lift: afterwards the moved ids are suppressed, so the render is
                // the hole rather than the drawing and comparing against it would assert nothing.
                let inkBefore = inkBounds(vector)
                XCTAssertTrue(lift(kind, manager, layerIndex), "\(label): the lift should have caught something")

                path.act(manager, layerIndex)

                XCTAssertTrue(vector.suppressedElementIDs.isEmpty,
                              "\(label): \(vector.suppressedElementIDs.count) element(s) still suppressed")
                XCTAssertNil(manager.vectorFloat, "\(label): the float outlived its teardown")
                // Nothing dropped: every id that was there before the lift is either still there, or
                // has been replaced by pieces — and either way the list can never be *shorter*.
                let idsAfter = Set(vector.elements.map(\.id))
                XCTAssertGreaterThanOrEqual(idsAfter.count, idsBefore.count,
                                            "\(label): the display list lost elements")
                XCTAssertFalse(vector.elements.isEmpty, "\(label): the display list was emptied")
                if let ink = path.ink {
                    guard let before = inkBefore else { return XCTFail("\(label): nothing rendered before the lift") }
                    guard let after = ink(manager, layerIndex) else {
                        return XCTFail("\(label): the flatten is blank — the whole cel was baked away")
                    }
                    XCTAssertEqual(after.minX, before.minX, accuracy: 1.5, "\(label): the flatten lost ink on the left")
                    XCTAssertEqual(after.maxX, before.maxX, accuracy: 1.5, "\(label): the flatten lost ink on the right")
                    XCTAssertEqual(after.minY, before.minY, accuracy: 1.5, "\(label): the flatten lost ink at the top")
                    XCTAssertEqual(after.maxY, before.maxY, accuracy: 1.5, "\(label): the flatten lost ink at the bottom")
                }
            }
        }
    }

    /// **Conservation of ink.** Lift a region and bake it without dragging it anywhere, and the
    /// drawing is pixel-identical to what it was before.
    ///
    /// This is the assertion that every split path has to pass through: a run boundary landed twice,
    /// a piece that lost its lattice, a fill cut with the wrong rule, an element left suppressed —
    /// each of them shows up here as a changed pixel, and none of them shows up anywhere else without
    /// somebody looking.
    ///
    /// Watched failing with `StrokeGeometry.membershipRuns` emitting the crossing sample only to the
    /// closing run, so the two halves no longer shared it: *Composites differ at (22, 15) channel A:
    /// got 182, expected 255* — one dab's worth of ink gone from the seam, which is exactly the
    /// amount a lost boundary sample costs.
    func testALiftAndBakeWithNoDragIsPixelIdenticalToTheDrawingBefore() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 18), to: CGPoint(x: 58, y: 18), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 46), to: CGPoint(x: 58, y: 46), size: 3))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 10, y: 26, width: 40, height: 10),
                                                      transform: nil),
                                         color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                                         opacity: 1))
        let before = cgImage(vector)

        select(manager, layerIndex, loop(CGRect(x: 22, y: 2, width: 26, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.commitVectorFloatIfNeeded()

        assertPixelsIdentical(cgImage(vector), before,
                              "A lift and a bake with no drag is not an edit, and must change no pixel.")
    }

    // MARK: - The split

    /// A stroke crossing the loop becomes exactly two elements **at the parent's index, outside
    /// first** — so a punch three elements above it is still above *both* halves.
    ///
    /// Appending the halves instead is the trap: it would hoist a moved half above every `.erase`
    /// element in the list, and a punch masks only what is beneath it, so a hole the artist made
    /// would silently stop applying.
    func testAStrokeCrossingTheLoopBecomesTwoElementsAtTheParentsIndexOutsideFirst() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 24, y: 20),
                                size: 8, composite: .erase))
        let punchID = vector.elements.last?.id

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        let elements = vector.elements
        XCTAssertEqual(elements.count, 3, "one stroke became two, the punch is untouched")
        XCTAssertEqual(elements[2].id, punchID, "the punch must stay at the top of the list")
        let float = manager.vectorFloat
        XCTAssertEqual(float?.insideIDs.count, 1, "exactly one half travels")
        XCTAssertFalse(float?.insideIDs.contains(elements[0].id) ?? true,
                       "the outside half is written first, so it is the one that stays")
        XCTAssertTrue(float?.insideIDs.contains(elements[1].id) ?? false,
                      "the inside half is written second, below the punch")
        // The centre of each half, to say which is which in artwork terms rather than by index.
        XCTAssertLessThan(elements[0].stroke?.samples.last?.x ?? 0, 31, "the stationary half is the left one")
        XCTAssertGreaterThan(elements[1].stroke?.samples.first?.x ?? 0, 29, "the travelling half is the right one")
    }

    /// A stroke **wholly** inside travels untouched — same id, same `DabLattice`. That is what stops
    /// a lasso re-rolling a scattering brush's pattern just by picking the stroke up.
    func testAStrokeWhollyInsideKeepsItsIdAndItsLattice() {
        let (manager, layerIndex, vector) = fixture()
        var drawn = stroke(from: CGPoint(x: 22, y: 22), to: CGPoint(x: 40, y: 22))
        drawn.lattice = DabLattice(samples: drawn.samples, parameters: [0, 1, 2], seedID: drawn.id)
        let originalID = drawn.id
        let originalLattice = drawn.lattice
        vector.addStroke(drawn)

        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 48, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        XCTAssertEqual(vector.elements.count, 1, "a wholly-inside stroke is not split")
        XCTAssertEqual(vector.elements.first?.id, originalID, "and keeps its identity")
        XCTAssertEqual(vector.elements.first?.stroke?.lattice, originalLattice, "and its dab phase")
        XCTAssertEqual(manager.vectorFloat?.insideIDs, [originalID])
    }

    /// **Selection is by the centre line, knowingly.** A 40 pt stroke whose spine lies outside the
    /// loop does not move, even though its ink is inside it.
    ///
    /// Asserted here as **correct**, not as a known defect — it is the owner's ruling of 2026-08-21,
    /// taken with this exact consequence put to them first. A later session reading this test must
    /// not "fix" it; the ink-accurate alternative is a named, deferred feature.
    func testAThickStrokeWhoseSpineIsOutsideDoesNotMoveEvenThoughItsInkIsInside() {
        let (manager, layerIndex, vector) = fixture()
        // Spine along y = 8; 40 pt wide, so its ink reaches down to y = 28.
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 8), to: CGPoint(x: 54, y: 8), size: 40))
        // The loop starts at y = 16 — well inside the ink, well outside the spine.
        select(manager, layerIndex, loop(CGRect(x: 4, y: 16, width: 56, height: 40)))

        XCTAssertFalse(manager.beginVectorLassoMove(),
                       "the spine is outside the loop, so nothing is caught — LASSO_MOVE.md §5.4")
        XCTAssertNil(manager.vectorFloat)
        XCTAssertNotNil(manager.selection, "and the loop stays on screen, ready to be redrawn")
    }

    /// A fill crossing the loop becomes two fills whose **rendered pixels**, composited, equal the
    /// original's.
    ///
    /// A pixel comparison rather than an assertion about the resulting paths' shape, because the
    /// question the fill arm has to get right is a *fill-rule* question and a path can be the right
    /// region drawn with the wrong rule.
    func testAFillCrossingTheLoopBecomesTwoFillsWhosePixelsEqualTheOriginal() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 44, height: 30),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        let before = cgImage(vector)

        select(manager, layerIndex, loop(CGRect(x: 24, y: 2, width: 40, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(vector.elements.count, 2, "one fill became two")
        XCTAssertEqual(manager.vectorFloat?.insideIDs.count, 1)
        manager.commitVectorFloatIfNeeded()

        assertPixelsIdentical(cgImage(vector), before, "the two halves must sum to the original fill")
    }

    /// Text whose centre is inside moves whole, with `pointSize` and the box untouched.
    func testTextWhoseCentreIsInsideMovesWholeAndKeepsItsPointSize() {
        let (manager, layerIndex, vector) = fixture()
        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 17
        let element = VectorTextElement(id: UUID(), recipe: recipe,
                                        frame: TextFrame(origin: CGPoint(x: 20, y: 20),
                                                          size: CGSize(width: 16, height: 10)))
        vector.upsertText(element)

        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 44, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(manager.vectorFloat?.insideIDs, [element.id])

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 8, dy: 0))
        let moved = vector.elements.compactMap(\.text).first
        XCTAssertEqual(moved?.recipe.typography.pointSize, 17, "a translation must not rescale type")
        XCTAssertEqual(moved?.frame.size, CGSize(width: 16, height: 10), "nor the layout box")
        XCTAssertEqual(moved?.frame.corners[0].x ?? -1, 28, accuracy: 1e-6, "all four corners translate")
        XCTAssertEqual(moved?.frame.corners[0].y ?? -1, 20, accuracy: 1e-6)
    }

    /// A self-intersecting lasso — the shape an artist makes the moment they loop back over their own
    /// line — partitions the drawing exactly as its normalized form does.
    ///
    /// Core Graphics leaves `intersection`/`subtracting` **undefined** for a non-simple path, so
    /// without the normalization at lift this is not merely inaccurate, it is unspecified.
    func testASelfIntersectingLassoPartitionsLikeItsNormalizedForm() {
        func partition(_ path: CGPath) -> Set<Int> {
            let (manager, layerIndex, vector) = fixture()
            for x in stride(from: 6, through: 58, by: 8) {
                vector.addStroke(stroke(from: CGPoint(x: CGFloat(x), y: 30),
                                        to: CGPoint(x: CGFloat(x) + 1, y: 31)))
            }
            select(manager, layerIndex, path)
            _ = manager.beginVectorLassoMove()
            let inside = manager.vectorFloat?.insideIDs ?? []
            return Set(vector.elements.enumerated().filter { inside.contains($0.element.id) }.map(\.offset))
        }
        // A bow tie: two lobes crossing in the middle, which is what a doubled-back lasso looks like.
        let tangled = CGMutablePath()
        tangled.addLines(between: [CGPoint(x: 4, y: 20), CGPoint(x: 60, y: 44),
                                   CGPoint(x: 60, y: 20), CGPoint(x: 4, y: 44)])
        tangled.closeSubpath()

        XCTAssertEqual(partition(tangled), partition(tangled.normalized(using: VectorCanvas.lassoFillRule)),
                       "a raw lasso and its normalized form must select the same strokes")
    }

    // MARK: - Ruling 1: an eraser mark is an ordinary element

    /// An `.erase` stroke takes the **same** centre-line containment test and the **same** split as a
    /// paint stroke: wholly in, it travels; wholly out, it stays; mixed, it becomes two independent
    /// erase strokes at the parent's index (owner, 2026-08-22).
    func testAnEraserMarkTakesTheSameContainmentTestAndSplitAsAPaintStroke() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 10))
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20),
                                size: 6, composite: .erase))

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        let erasers = vector.elements.filter { $0.stroke?.composite == .erase }
        XCTAssertEqual(erasers.count, 2, "the punch splits at the loop like any other stroke")
        let inside = manager.vectorFloat?.insideIDs ?? []
        XCTAssertEqual(erasers.filter { inside.contains($0.id) }.count, 1,
                       "and exactly the half inside the loop travels")
    }

    /// **A float made only of eraser marks renders blank, and that is not an error.** A punch has no
    /// ink of its own; drawn alone into a transparent bitmap it draws nothing. The lift still
    /// succeeds, the piece is still real geometry, and the hole lands where it is dropped.
    func testAFloatOfOnlyEraserMarksRendersBlankAndStillMovesItsHole() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 32), to: CGPoint(x: 60, y: 32), size: 24))
        vector.addStroke(stroke(from: CGPoint(x: 14, y: 32), to: CGPoint(x: 18, y: 32),
                                size: 10, composite: .erase))

        select(manager, layerIndex, loop(CGRect(x: 8, y: 24, width: 16, height: 16)))
        XCTAssertTrue(manager.beginVectorLassoMove(), "a lasso holding only a punch still lifts")
        guard let float = manager.vectorFloat else { return XCTFail("no float") }
        XCTAssertEqual(float.insideIDs.count, 1)

        let isolated = vector.renderIsolated(ids: float.insideIDs)
        XCTAssertNotNil(isolated, "the float still has an image, even though it is empty")
        XCTAssertNil(PixelOps.opaqueContentBounds(isolated!),
                     "and it is legitimately blank — nothing may read that as 'nothing was selected'")

        // The hole travels: after moving it right, the pixel it used to clear is painted again and the
        // pixel it now covers is clear.
        let holeWasAt = CGPoint(x: 16, y: 32)
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 24, dy: 0))
        manager.commitVectorFloatIfNeeded()
        XCTAssertTrue(isOpaque(vector, at: holeWasAt), "the hole no longer bites where it was")
        XCTAssertFalse(isOpaque(vector, at: CGPoint(x: holeWasAt.x + 24, y: holeWasAt.y)),
                       "it bites where it landed instead")
    }

    // MARK: - The nudge

    /// **The ink moves, not only the samples.** `stamp` draws from `lattice?.samples ?? samples`, so
    /// mapping `samples` and leaving the lattice behind moves the geometry and not one pixel.
    ///
    /// Watched failing with the `if var lattice = stroke.lattice` arm of `VectorCanvas.mapping`
    /// removed: *("0.0") is not equal to ("12.0") +/- ("1.5")* — the samples moved twelve points and
    /// the rendered ink did not move at all.
    func testANudgeMovesTheRenderedInkAndNotOnlyTheSamples() {
        let (manager, layerIndex, vector) = fixture()
        // Crossing the loop, so the travelling half is a *split piece* and therefore carries a
        // lattice — which is the only case where the two can disagree.
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.commitVectorFloatIfNeeded()

        // Re-lift just the piece so the "before" and "after" pictures are of the same geometry.
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let float = manager.vectorFloat, let movedID = float.insideIDs.first else {
            return XCTFail("no float")
        }
        XCTAssertNotNil(vector.elements.first { $0.id == movedID }?.stroke?.lattice,
                        "fixture precondition: the travelling piece carries a parent lattice")
        manager.cancelVectorFloat()
        let inkBefore = inkBounds(vector)
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 0, dy: 12))
        manager.commitVectorFloatIfNeeded()

        guard let inkBefore, let inkAfter = inkBounds(vector) else { return XCTFail("nothing rendered") }
        XCTAssertEqual(inkAfter.maxY - inkBefore.maxY, 12, accuracy: 1.5,
                       "the rendered ink must follow the nudge, not only the stored samples")
    }

    /// **The bake identity.** A zero-delta nudge changes no sample and no pixel — including on a
    /// layer whose own transform is neither identity nor a pure translation, which is the only case
    /// where `.concatenating(baseTransform.inverted())` can be wrong.
    ///
    /// The rotated case was added with the corner and rotate handles: `mapping` now reads
    /// `hypot(t.a, t.b)` and `atan2(t.b, t.a)` off the delta, so a base transform that is not
    /// axis-aligned is on the bake path in a way it was not before, and a zero-delta nudge is where a
    /// mis-derived scale or angle would show up as a piece that jumps the moment it is picked up.
    func testAZeroDeltaNudgeChangesNoSampleAndNoPixelOnATransformedLayer() {
        for transform in [CGAffineTransform.identity,
                          CGAffineTransform(translationX: 7, y: -3).scaledBy(x: 1.4, y: 1.4),
                          CGAffineTransform(rotationAngle: 0.4).concatenating(
                            CGAffineTransform(translationX: 6, y: 9))] {
            let (manager, layerIndex, vector) = fixture()
            vector.setTransform(transform)
            vector.addStroke(stroke(from: CGPoint(x: 6, y: 22), to: CGPoint(x: 40, y: 22), size: 5))
            vector.addStroke(stroke(from: CGPoint(x: 6, y: 34), to: CGPoint(x: 40, y: 34), size: 5))
            // The loop is CANVAS space; the stored geometry is LOCAL. On a transformed layer the two
            // are different rectangles, and skipping the mapping is silently wrong here and only here.
            // Built as a transformed *path* rather than `CGRect.applying`, which answers with a
            // bounding box and so would quietly select a different set of strokes once the layer is
            // turned.
            let localLoop = CGRect(x: 20, y: 4, width: 40, height: 50)
            var mapping = transform
            let canvasLoop = CGPath(rect: localLoop, transform: &mapping)
            // Both taken *before* the lift: after it the moved ids are suppressed, so the render is
            // the hole rather than the drawing, and comparing against that would assert nothing.
            let pixelsBefore = cgImage(vector)
            select(manager, layerIndex, canvasLoop)
            XCTAssertTrue(manager.beginVectorLassoMove(), "transform \(transform)")
            guard let float = manager.vectorFloat else { return XCTFail("no float") }

            let samplesBefore = vector.elements.compactMap(\.stroke).map(\.samples)
            manager.nudgeVectorFloat(to: float.frame.transform)   // exactly where it was lifted
            let samplesAfter = vector.elements.compactMap(\.stroke).map(\.samples)

            XCTAssertEqual(samplesBefore.count, samplesAfter.count)
            for (before, after) in zip(samplesBefore, samplesAfter) {
                XCTAssertEqual(before.count, after.count)
                for (a, b) in zip(before, after) {
                    XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "transform \(transform)")
                    XCTAssertEqual(a.y, b.y, accuracy: 1e-9, "transform \(transform)")
                }
            }
            manager.commitVectorFloatIfNeeded()
            assertPixelsIdentical(cgImage(vector), pixelsBefore, "transform \(transform)")
        }
    }

    /// A nudge on a transformed layer lands the ink where the box was dragged, in **canvas** points —
    /// which is the assertion that catches a delta applied in the wrong space.
    func testANudgeOnAScaledLayerMovesTheInkByTheCanvasDistanceDragged() {
        let (manager, layerIndex, vector) = fixture()
        vector.setTransform(CGAffineTransform(scaleX: 2, y: 2))
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 8), to: CGPoint(x: 12, y: 8), size: 2))
        let before = inkBounds(vector)
        select(manager, layerIndex, loop(CGRect(x: 0, y: 0, width: 40, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 10, dy: 0))
        manager.commitVectorFloatIfNeeded()

        guard let before, let after = inkBounds(vector) else { return XCTFail("nothing rendered") }
        XCTAssertEqual(after.midX - before.midX, 10, accuracy: 1.0,
                       "a 10 pt drag on a 2× layer is 10 canvas points, not 5 and not 20")
    }

    // MARK: - Undo

    /// **Four nudges are four steps, and the fourth press gives back the unsplit stroke.**
    ///
    /// The last half is the ruling of 2026-08-22: the cut was something the move did to make itself
    /// possible, not an edit the artist asked for, so undoing past the move rejoins the line.
    func testFourNudgesAreFourStepsAndTheLastOneGivesBackTheUnsplitStroke() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        let originalID = vector.elements[0].id
        let elementsBefore = vector.elements
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(vector.elements.count, 2, "the lift split the stroke")

        let stepsAtLift = manager.history.undoStack.count
        // Four separate gestures of 4 pt each — `movedBy` measures from where the box is *now*, which
        // is what a real drag does.
        for _ in 1...4 { manager.nudgeVectorFloat(to: movedBy(manager, dx: 4, dy: 0)) }
        XCTAssertEqual(manager.history.undoStack.count - stepsAtLift, 4, "one step per nudge, and no more")

        // The travelling half's own geometry, which is where a nudge lands. (The *rendered* image is
        // the hole while the piece is floating, so it says nothing about where the piece is.)
        func travellingX() -> CGFloat? {
            guard let inside = manager.vectorFloat?.insideIDs else { return nil }
            return vector.elements.first { inside.contains($0.id) }?.stroke?.samples.first?.x
        }
        XCTAssertEqual(travellingX() ?? 0, 34 + 16, accuracy: 1.0, "four drags of 4, 8, 12, 16 land at +16")
        let boxAfterFour = manager.vectorFloat?.frame.transform.position.x ?? 0
        manager.undo()
        XCTAssertNotNil(manager.vectorFloat, "the first press leaves the piece floating")
        XCTAssertEqual(travellingX() ?? 0, 34 + 12, accuracy: 1.0, "and walks back exactly one drag")
        XCTAssertEqual((manager.vectorFloat?.frame.transform.position.x ?? 0) - boxAfterFour, -4,
                       accuracy: 1e-6, "the box follows the geometry back rather than staying put")
        manager.undo()
        manager.undo()
        XCTAssertNotNil(manager.vectorFloat, "three presses in, the float is still alive")
        XCTAssertEqual(travellingX() ?? 0, 34 + 4, accuracy: 1.0)
        manager.undo()

        XCTAssertNil(manager.vectorFloat, "the fourth press ends the float")
        XCTAssertEqual(vector.elements.count, 1, "and gives back one stroke, not two halves")
        XCTAssertEqual(vector.elements[0].id, originalID, "the very stroke that was there before")
        XCTAssertEqual(vector.elements[0].stroke?.samples.count, elementsBefore[0].stroke?.samples.count)
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
        XCTAssertNotNil(manager.selection, "and puts the loop back on screen")
    }

    /// A lift the artist never dragged is un-happened by undo rather than stepped back from: there is
    /// no step behind it, and leaving the split in place would be a document change nobody made.
    func testLiftWithZeroNudgesThenUndoRestoresVerbatimAndRecordsNoStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        let before = vector.elements
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        let stepsBefore = manager.history.undoStack.count
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertTrue(manager.canUndo, "undo must be lit — it closes a hole the artist can see")

        manager.undo()

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore, "no step was recorded, and none consumed")
        XCTAssertEqual(vector.elements.count, before.count)
        XCTAssertEqual(vector.elements[0].id, before[0].id, "restored verbatim, not re-split")
        XCTAssertNil(manager.vectorFloat)
    }

    // MARK: - Ruling 3: an empty lasso does nothing

    /// A loop over blank paper plus Move does **nothing** — it does not fall back to moving the whole
    /// cel, and the loop stays on screen ready to be redrawn (owner, 2026-08-22).
    func testAnEmptyLassoDoesNothingAndLeavesTheLoopOnScreen() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 8), to: CGPoint(x: 20, y: 8)))
        let before = vector.elements
        let emptyRegion = loop(CGRect(x: 30, y: 40, width: 20, height: 20))
        select(manager, layerIndex, emptyRegion)

        XCTAssertFalse(manager.beginVectorLassoMove())
        XCTAssertNil(manager.vectorFloat, "nothing lifted")
        XCTAssertEqual(vector.elements.count, before.count, "and nothing moved")
        XCTAssertEqual(vector.transform, .identity, "and the whole cel emphatically did not move")
        XCTAssertNotNil(manager.selection, "the loop stays, ready to be redrawn")
    }

    // MARK: - The marching ants (§5.6)

    /// The ants **travel with the piece** and clear **at the bake**, not at the lift — and since the
    /// box gained its corners and its knob, they scale and turn with it too.
    ///
    /// That second half had to be checked rather than assumed. `moving(_:by:)` is a plain
    /// `path.copy(using:)`, which carries any affine, but the affine it is handed comes from
    /// `canvasDelta(of:at:)` composing `baseTransform.inverted()` with `affine(from:pivot:)` — and
    /// `affine(from:pivot:)` builds translate·rotate·scale·translate(-pivot), so the pivot has to be
    /// the one the box's transform was derived about or the ants land beside the ink rather than on
    /// it. The assertion is the loop's own corner, scaled about the box centre.
    func testTheSelectionTravelsWithTheFloatAndClearsAtTheBake() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 40, y: 20)))
        let loopRect = CGRect(x: 10, y: 10, width: 44, height: 30)
        select(manager, layerIndex, loop(loopRect))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertNotNil(manager.selection, "the loop survives the lift — §5.6 clears it at the bake")
        XCTAssertEqual(manager.selection?.bounds.origin.x ?? -1, loopRect.origin.x, accuracy: 1e-6)

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 9, dy: -4))
        XCTAssertEqual(manager.selection?.bounds.origin.x ?? 0, loopRect.origin.x + 9, accuracy: 1e-6,
                       "one transform on the path, and the ants are where the piece is")
        XCTAssertEqual(manager.selection?.bounds.origin.y ?? 0, loopRect.origin.y - 4, accuracy: 1e-6)

        // A corner drag to 2×, from the box wherever the move left it. The loop's top-left must land
        // where the box centre scales it to, and the loop must be twice the size.
        guard let centre = manager.vectorFloat?.frame.transform.position else { return XCTFail("no float") }
        let cornerBefore = manager.selection?.bounds.origin ?? .zero
        manager.nudgeVectorFloat(to: scaledBy(manager, 2))
        XCTAssertEqual(manager.selection?.bounds.origin.x ?? 0,
                       centre.x + (cornerBefore.x - centre.x) * 2, accuracy: 1e-4,
                       "the ants scale about the same centre the ink does")
        XCTAssertEqual(manager.selection?.bounds.origin.y ?? 0,
                       centre.y + (cornerBefore.y - centre.y) * 2, accuracy: 1e-4)
        XCTAssertEqual(manager.selection?.bounds.width ?? 0, loopRect.width * 2, accuracy: 1e-4)

        manager.commitVectorFloatIfNeeded()
        XCTAssertNil(manager.selection, "and they clear on commit")
    }

    /// **The raster Move inherits the same rule** (owner, 2026-08-22): its selection clears at the
    /// bake, not at the lift, so the two tools behave the same way on the same gesture.
    func testRasterMoveKeepsItsSelectionUntilTheBake() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 10, y: 10, width: 20, height: 20)))
        manager.selection = Selection(path: CGPath(rect: CGRect(x: 8, y: 8, width: 24, height: 24), transform: nil),
                                      bounds: CGRect(x: 8, y: 8, width: 24, height: 24),
                                      layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)

        manager.beginMove()
        XCTAssertNotNil(manager.floatingPiece, "fixture precondition: something lifted")
        XCTAssertNotNil(manager.selection, "the outline survives the lift, as the vector tool's does")

        manager.commitFloatingPieceIfNeeded()
        XCTAssertNil(manager.selection, "and clears at the bake")
    }

    // MARK: - Staleness, and the render budget

    /// A float whose canvas moved under it abandons cleanly rather than splicing against a list it no
    /// longer describes.
    func testAFloatWhoseSourceChangedUnderItAbandonsRatherThanSplicing() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30)))
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        // Something else edits the cel — an undo of an earlier action, a script, anything.
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 50), to: CGPoint(x: 20, y: 50)))
        vector.bumpVersion()

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 20, dy: 0))
        XCTAssertNil(manager.vectorFloat, "the float abandoned rather than writing against stale state")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty, "and left nothing suppressed behind it")
    }

    /// **Three canvas rasterizations for the whole move, however many times it is nudged.**
    ///
    /// A count, not a duration: the claim is about the design — the moved ids are suppressed for the
    /// float's life, so the source's pixels genuinely do not change between nudges — and asserting it
    /// in milliseconds would be asserting about the machine instead.
    func testTheRenderCountForAWholeMoveDoesNotGrowWithTheNumberOfNudges() {
        func rasterizations(nudges: Int) -> Int {
            let (manager, layerIndex, vector) = fixture()
            for i in 0..<6 {
                vector.addStroke(stroke(from: CGPoint(x: 4, y: CGFloat(6 + i * 8)),
                                        to: CGPoint(x: 60, y: CGFloat(6 + i * 8))))
            }
            _ = vector.render()                       // the picture the artist is already looking at
            select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
            let before = vector.rasterizations
            XCTAssertTrue(manager.beginVectorLassoMove())
            _ = vector.render()                       // the hole
            _ = vector.renderIsolated(ids: manager.vectorFloat?.insideIDs ?? [])   // the float
            for i in 1...max(nudges, 1) where nudges > 0 {
                manager.nudgeVectorFloat(to: movedBy(manager, dx: CGFloat(i), dy: 0))
            }
            manager.commitVectorFloatIfNeeded()
            _ = vector.render()                       // the bake
            return vector.rasterizations - before
        }
        XCTAssertEqual(rasterizations(nudges: 1), 3, "the hole, the float, and the bake")
        XCTAssertEqual(rasterizations(nudges: 12), 3, "and twelve nudges cost exactly the same")
    }

    // MARK: - Ruling (j): a touch away from the box puts it down

    /// **Tapping away from a floating piece settles it, and settles it the way every other door
    /// does** — owner's ruling, 2026-08-22, closing the asymmetry with the raster Move tool, whose
    /// `FloatingPieceOverlayView` has always committed on a tap outside.
    ///
    /// The undo accounting is the part that had to be checked rather than assumed, because §5's
    /// "undo is one step per nudge" is a settled ruling and a new commit door is exactly where a
    /// second step gets recorded by accident. One drag, one step — and the commit adds none of its
    /// own, because the nudge already wrote it. The single press then walks the artist all the way
    /// back: it is the *first* nudge's step, so it un-does the split with it and gives back the
    /// stroke that was there before, un-cut.
    ///
    /// The two halves are asserted together on purpose. `CanvasTouchOwner` says the tap away from the
    /// box belongs to `.moveBoxCommit`; `commitVectorFloatIfNeeded()` is what that handler calls, and
    /// is the same call `TopToolbar.toggleMove`'s vector-float branch makes. Driving the model call
    /// alone would leave "and it is actually reached by a tap" unstated.
    ///
    /// Watched failing with the plausible wrong answer written in — a commit that writes the box's
    /// final position on its way out, `nudgeVectorFloat(to: float.frame.transform)` inside
    /// `commitVectorFloatIfNeeded`. It is the shape the raster path has (`commitFloatingPieceIfNeeded`
    /// really does register a cel change of its own), it is a *zero-delta* nudge so it moves nothing
    /// visible, and it went red on five assertions at once: *2 step(s) for one drag and a tap*, and
    /// then the undo landing one drag short — *one stroke back, not two halves* with the stroke still
    /// cut in half and its far sample at 34 instead of 60.
    ///
    /// (`commitAllInteractiveState()` in place of `commitVectorFloatIfNeeded()` was tried as the
    /// counterfactual first and is **not** one: it routes to the same call and records the same single
    /// step. Worth knowing before someone reaches for it as an equivalent.)
    func testATapAwayFromTheBoxCommitsInOneUndoStepAndUndoPutsThePieceBack() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        let originalID = vector.elements[0].id
        let samplesBefore = vector.elements[0].stroke?.samples.map(\.x)
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))

        let stepsBefore = manager.history.undoStack.count
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 6, dy: 0))

        // The touch that follows: away from the box, on a vector layer with a float up. This is the
        // arbitration `handleMoveBoxCommit` performs before it calls anything.
        let awayFromTheBox = CanvasTouchInputs(tool: manager.selectedTool, hasVectorFloat: true,
                                              activeLayer: .vector, chrome: .none)
        XCTAssertEqual(CanvasTouchOwner.owner(in: awayFromTheBox), .moveBoxCommit,
                       "the tap is the box's to take")
        manager.commitVectorFloatIfNeeded()

        XCTAssertNil(manager.vectorFloat, "the piece is down")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty, "and nothing is left suppressed")
        XCTAssertEqual(manager.history.undoStack.count - stepsBefore, 1,
                       "\(manager.history.undoStack.count - stepsBefore) step(s) for one drag and a tap")

        manager.undo()

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore, "and the one step is spent")
        XCTAssertEqual(vector.elements.count, 1, "one stroke back, not two halves")
        XCTAssertEqual(vector.elements[0].id, originalID, "the very stroke that was there before")
        XCTAssertEqual(vector.elements[0].stroke?.samples.map(\.x), samplesBefore,
                       "every sample back where it started")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
        XCTAssertNotNil(manager.selection, "and the loop is back on screen to be redrawn")
    }

    // MARK: - The corner and rotate handles

    /// **A scaled piece gets thicker, not merely longer.**
    ///
    /// This is the one assertion that catches the defect the `allowedHandles: [.body]` restriction
    /// existed to prevent. `VectorCanvas.mapping` maps sample *points*; `BrushStamper` stamps with
    /// the scalar `stroke.size`. Scale the spine and leave the scalar alone and the ink spreads along
    /// its length and keeps its old width — and because the live preview is a `UIView.transform` on a
    /// bitmap, the drag *looks* right and only the bake is wrong.
    ///
    /// Watched failing with the stroke arm's `stroke.size *= k` absent, i.e. exactly today's `main`:
    /// *("8.0") is not equal to ("16.0")* on the height — a spine spread 2× with its width untouched
    /// — and *("40.0") is not equal to ("48.0")* on the width, which is the same defect seen from the
    /// other side: 16 pt of spine doubled to 32 while the 8 pt of dab that pads each end did not.
    func testAScaledFloatKeepsItsInkWeightRelativeToItsSpine() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 8))
        guard let before = inkBounds(vector) else { return XCTFail("nothing rendered") }

        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.nudgeVectorFloat(to: scaledBy(manager, 2))
        manager.commitVectorFloatIfNeeded()

        guard let after = inkBounds(vector) else { return XCTFail("nothing rendered") }
        // A pixel and a half, for the grid: Hard Round's 0.95 hardness leaves no measurable fringe for
        // `opaqueContentBounds` (`alpha > 0`) to pick up — the source measured 24 × 8 for a 16 pt
        // spine with an 8 pt dab, exactly the geometry — so this is rounding, not softness.
        XCTAssertEqual(after.width, before.width * 2, accuracy: 1.5, "the spine spread 2×")
        XCTAssertEqual(after.height, before.height * 2, accuracy: 1.5,
                       "and the ink got 2× thicker with it — the half that fails when `size` is left alone")
    }

    /// **The exactness claim, measured where it is made.** Under a similarity — translate, rotate,
    /// uniform scale — scaling `stroke.size` by the same factor is not an approximation: the walk is
    /// similar to itself, dab for dab.
    ///
    /// `stampSpacing` is linear in brush size and `advance` walks in geometric distance, so a path
    /// *k*× longer walked with *k*× spacing takes the identical number of steps at the identical
    /// parameters. That gives an identical dab count (so the seeded `DabRNG` draws the identical
    /// sequence), identical `visibleRange` selection for a lattice-carrying piece, and every dab
    /// exactly where the similarity puts it, at exactly *k*× the radius.
    ///
    /// Run on a **cut** piece on purpose: a piece carries its parent's samples in a `DabLattice` and
    /// renders a sub-run of the parent's walk, which is the only case where the geometry and the ink
    /// can disagree.
    ///
    /// The similarity compared against is built here from the scale factor and the box centre, not
    /// taken from `VectorCanvas.affine` — the transform is an input to the claim, not the claim.
    ///
    /// Watched failing with `stroke.size *= k` absent: *("29") is not equal to ("15")* — the same
    /// spacing over a path twice as long is twice as many dabs, and no assertion about position could
    /// even be reached.
    func testAScaledPieceLandsEveryDabWhereTheSimilarityPutsIt() {
        let (manager, layerIndex, vector) = fixture()
        // `spacingFraction` 0.25 at size 8 gives a 2 pt spacing, and 4 pt when doubled — both clear
        // of `stampSpacing`'s 1 pt floor, which is the one thing that breaks the similarity. See
        // `testTheSpacingFloorIsTheOnePlaceAScaleChangesTheDabCount`.
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = 0.25
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 32), to: CGPoint(x: 58, y: 32),
                                size: 8, brush: brush))
        let loopRect = CGRect(x: 30, y: 16, width: 28, height: 32)
        select(manager, layerIndex, loop(loopRect))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let float = manager.vectorFloat, let movedID = float.insideIDs.first,
              let lifted = vector.elements.first(where: { $0.id == movedID })?.stroke else {
            return XCTFail("no float")
        }
        XCTAssertNotNil(lifted.lattice, "fixture precondition: the travelling piece carries a parent lattice")

        let k: CGFloat = 2
        let centre = float.frame.transform.position
        let similarity = CGAffineTransform(translationX: centre.x, y: centre.y)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -centre.x, y: -centre.y)
        let expected = dabs(of: lifted).map { (point: $0.point.applying(similarity), radius: $0.radius * k) }

        manager.nudgeVectorFloat(to: scaledBy(manager, k))

        guard let scaled = vector.elements.first(where: { $0.id == movedID })?.stroke else {
            return XCTFail("the piece vanished")
        }
        let actual = dabs(of: scaled)
        XCTAssertEqual(actual.count, expected.count,
                       "a k× path walked with k× spacing takes the same number of steps")
        guard actual.count == expected.count else { return }
        for (i, (a, e)) in zip(actual, expected).enumerated() {
            XCTAssertEqual(a.point.x, e.point.x, accuracy: 1e-9, "dab \(i)")
            XCTAssertEqual(a.point.y, e.point.y, accuracy: 1e-9, "dab \(i)")
            XCTAssertEqual(a.radius, e.radius, accuracy: 1e-9, "dab \(i)'s radius")
        }
    }

    /// **The documented exception, pinned rather than inherited.** `stampSpacing` floors at 1 pt, so
    /// below `brushSize * spacingFraction == 1` the spacing stops being linear in size and the walk
    /// stops being similar to itself: the scaled stroke gets *more* dabs than similarity predicts,
    /// packed closer together relative to its own width.
    ///
    /// That floor binds at ordinary sizes, not only at hairlines — Hard Round's `spacingFraction` is
    /// 0.05, so it binds below 20 pt, and the Pen's is 0.03, so it binds below 33 pt. It costs no ink
    /// (dab diameter still scales, so the stroke is the right weight and still solid) and it re-rolls
    /// nothing visible, because every built-in brush has `scatter` and `rotationJitter` at zero and a
    /// round dab does not care what the RNG said. Recorded here so a later reading of
    /// `testAScaledPieceLandsEveryDabWhereTheSimilarityPutsIt` cannot mistake its brush for an
    /// arbitrary choice.
    func testTheSpacingFloorIsTheOnePlaceAScaleChangesTheDabCount() {
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = 0.05
        let line = [VectorSample(x: 0, y: 0, pressure: 1), VectorSample(x: 40, y: 0, pressure: 1)]
        func walk(size: CGFloat, scale k: CGFloat) -> Int {
            let target = RecordingDabTarget()
            BrushStamper.stampStroke(into: target,
                                     samples: line.map {
                                         BrushStamper.Sample(point: CGPoint(x: $0.x * k, y: $0.y * k),
                                                             pressure: $0.pressure)
                                     },
                                     brush: brush, color: .black, brushSize: size * k,
                                     brushOpacity: 1, seed: 99)
            return target.dabs.count
        }
        // Clear of the floor at both sizes: 40 × 0.05 = 2 pt, doubling to 4 pt.
        XCTAssertEqual(walk(size: 40, scale: 2), walk(size: 40, scale: 1),
                       "above the floor the dab count is scale-invariant")
        // Under it at both sizes: 4 × 0.05 = 0.2 pt, floored to 1 pt on each side, so the 2× path
        // simply gets twice as many 1 pt steps.
        XCTAssertEqual(walk(size: 4, scale: 2), walk(size: 4, scale: 1) * 2 - 1,
                       "under the floor the spacing stops scaling and the count doubles instead")
    }

    /// **Down through the spacing floor and back out gives the identical walk** — and the floor is
    /// not something the Move tool created.
    ///
    /// Two claims, and TODO item (14) had both of them the other way round. `stampSpacing` is
    /// `max(brushSize * spacingFraction, 1)`: it floors whatever scalar it is handed, at native
    /// sizes, with no transform anywhere near it — Hard Round's fraction is 0.05, so a 9 pt brush
    /// wants 0.45 pt of spacing and gets 1 pt, on a cel nobody ever lassoed. Nothing about a Move
    /// creates it, and no amount of precision removes it: it is an absolute constant inside a
    /// relative walk, so it is the *ratio* between the two that a shrink destroys.
    ///
    /// What a Move could have done is fail to come back, and it does not. Every nudge maps
    /// `float.liftedInside` — the elements exactly as the lift produced them — so the scalar reaching
    /// the walk is the box's own accumulated factor rather than a running geometry, and there is no
    /// term for an error to land in. `0.02 * 50` is **bit-exactly** 1 in IEEE double, which is why
    /// the third walk here is not merely close to the first; the assertion below spends a line saying
    /// so, because "and back" is the whole claim and a `1.0000000000000002` would make it a different
    /// test. `testAScaleOutAndBackIsPixelIdentical` is the same finding one level up, in pixels.
    func testTheSpacingFloorSurvivesAScaleRoundTrip() {
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = 0.05
        let line = [VectorSample(x: 0, y: 0, pressure: 1), VectorSample(x: 40, y: 0, pressure: 1)]
        func walk(size: CGFloat, scale k: CGFloat) -> Int {
            let target = RecordingDabTarget()
            BrushStamper.stampStroke(into: target,
                                     samples: line.map {
                                         BrushStamper.Sample(point: CGPoint(x: $0.x * k, y: $0.y * k),
                                                             pressure: $0.pressure)
                                     },
                                     brush: brush, color: .black, brushSize: size * k,
                                     brushOpacity: 1, seed: 99)
            return target.dabs.count
        }

        // The two box scalars a corner drag out to 2% and back would leave behind, multiplied the
        // way `scaledBy` multiplies them.
        let out: CGFloat = 0.02, back: CGFloat = 50
        let roundTrip = out * back
        XCTAssertEqual(roundTrip, 1,
                       "0.02 × 50 is exactly 1 in double, so the round trip is a return and not an approach")

        let native = walk(size: 40, scale: 1)
        let shrunk = walk(size: 40, scale: out)
        let regrown = walk(size: 40, scale: roundTrip)

        // 40 pt of brush wants 2 pt of spacing and gets it; 0.8 pt wants 0.04 and is floored to 1,
        // which is longer than the whole shrunk stroke.
        XCTAssertNotEqual(shrunk, native,
                          "under the floor the walk is a different walk: \(shrunk) dabs against \(native)")
        XCTAssertEqual(regrown, native,
                       "and coming back out of the floor gives it back exactly: \(regrown) against \(native)")
    }

    /// **A rotated piece is the same ink turned.** The dab set is the source's, mapped — so the ink's
    /// box transposes under a quarter turn and the amount of ink is conserved.
    ///
    /// The pixel *count* rather than a pixel comparison: a turned raster is resampled onto a
    /// different set of grid cells, so pinning bytes would be pinning the rasterizer. Count is the
    /// conservation quantity, and it catches ink loss without pinning resampling.
    func testARotatedFloatIsTheSameInkTurned() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32), size: 6))
        guard let before = inkBounds(vector) else { return XCTFail("nothing rendered") }
        let inkBefore = opaquePixelCount(vector)

        select(manager, layerIndex, loop(CGRect(x: 12, y: 22, width: 40, height: 20)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.nudgeVectorFloat(to: turnedBy(manager, .pi / 2))
        manager.commitVectorFloatIfNeeded()

        guard let after = inkBounds(vector) else { return XCTFail("nothing rendered") }
        XCTAssertEqual(after.width, before.height, accuracy: 1.5, "a quarter turn transposes the box")
        XCTAssertEqual(after.height, before.width, accuracy: 1.5)
        XCTAssertEqual(Double(opaquePixelCount(vector)), Double(inkBefore),
                       accuracy: Double(inkBefore) * 0.1,
                       "and turning ink does not destroy any of it")
    }

    /// **A lift, a scale out and back, and a bake leave the drawing pixel-identical** — §8.1's
    /// conservation test, and the one that would catch a `size` that accumulated instead of being
    /// derived.
    ///
    /// It is not trivially true. Every nudge maps `float.liftedInside`, the elements exactly as the
    /// split produced them, so the map is absolute from the lift and the round trip is a return to
    /// the identity. An implementation that scaled the *current* geometry instead would come back at
    /// 4× — and would drift on every intermediate drag besides.
    ///
    /// Watched failing with the nudge written to accumulate — `mapping(element, ...)` in place of
    /// `mapping(lifted, ...)` at `CanvasManager+LassoMove.swift`, the one-word change that turns an
    /// absolute map into an incremental one: *Composites differ at (26, 0) channel A: got 142,
    /// expected 0*, i.e. ink 26 points up the canvas that the drawing never had, from a piece that
    /// came back at 2.5³ rather than at 1.
    func testAScaleOutAndBackIsPixelIdentical() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 26), to: CGPoint(x: 40, y: 26), size: 5))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 26, y: 34, width: 12, height: 6),
                                                      transform: nil),
                                         color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                                         opacity: 1))
        let before = cgImage(vector)

        select(manager, layerIndex, loop(CGRect(x: 14, y: 16, width: 36, height: 32)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let lift = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        manager.nudgeVectorFloat(to: scaledBy(manager, 2.5))
        manager.nudgeVectorFloat(to: turnedBy(manager, 0.7))
        manager.nudgeVectorFloat(to: lift)          // the box dragged back to exactly where it started
        manager.commitVectorFloatIfNeeded()

        assertPixelsIdentical(cgImage(vector), before,
                              "a scale out and back is not an edit, and must change no pixel")
    }

    /// **Every kind travels under a scale, and each in its own currency.** A stroke's is `size`, a
    /// placed image's is `LayerTransform.scale`/`rotation`, a fill's is nothing at all (a `CGPath`
    /// carries any affine), and text's is its corners *with* its layout box and its point size.
    ///
    /// Text is the one that has to be argued rather than assumed. Scaling `corners` alone would draw
    /// correctly — `TextFrame.affineTransform` is the ratio of the corners to `size` — but it breaks
    /// the invariant `TextFrame.Basis` states, that `basis.width == size.width` for every frame this
    /// project writes. `TextFrameDrag.resized` and `TextFrame.resized(to:)` both read `basis.width`
    /// as a layout extent and write it back into `size`, so the first handle drag or the first
    /// keystroke into a still-`autoSize` box after a lasso scale would snap the type back to its old
    /// size. Scaling `size` and `pointSize` with the corners keeps the invariant, keeps the same
    /// words on the same lines, and leaves `autoSize` meaningful.
    ///
    /// Watched failing with `mapping`'s `.image` arm left at position-only: *("1.0") is not equal to
    /// ("2.0")* — the photo stayed its original size while everything around it doubled.
    func testAScaledFloatCarriesItsPlacedImageAndItsText() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 28, y: 24), to: CGPoint(x: 36, y: 24), size: 3))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 28, y: 28, width: 8, height: 4),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 36),
                                                                     scale: 1, rotation: 0)))
        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 12
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 32, y: 38),
                                                             size: CGSize(width: 10, height: 6))))

        select(manager, layerIndex, loop(CGRect(x: 20, y: 16, width: 28, height: 32)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let float = manager.vectorFloat else { return XCTFail("no float") }
        XCTAssertEqual(float.insideIDs.count, 4, "all four kinds travel")
        let centre = float.frame.transform.position
        func scaledAbout(_ p: CGPoint, _ k: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + (p.x - centre.x) * k, y: centre.y + (p.y - centre.y) * k)
        }
        guard let fillBefore = vector.elements.compactMap(\.fill).first?.cgPath?.boundingBoxOfPath else {
            return XCTFail("no fill")
        }

        manager.nudgeVectorFloat(to: scaledBy(manager, 2))

        guard let image = vector.elements.compactMap(\.image).first else { return XCTFail("no image") }
        XCTAssertEqual(image.transform.scale, 2, accuracy: 1e-9, "a placed image resizes with the piece")
        XCTAssertEqual(image.transform.position.x, scaledAbout(CGPoint(x: 30, y: 36), 2).x, accuracy: 1e-6)
        XCTAssertEqual(image.transform.position.y, scaledAbout(CGPoint(x: 30, y: 36), 2).y, accuracy: 1e-6)

        guard let text = vector.elements.compactMap(\.text).first else { return XCTFail("no text") }
        XCTAssertEqual(text.frame.corners[0].x, scaledAbout(CGPoint(x: 32, y: 38), 2).x, accuracy: 1e-6)
        XCTAssertEqual(text.frame.corners[0].y, scaledAbout(CGPoint(x: 32, y: 38), 2).y, accuracy: 1e-6)
        XCTAssertEqual(text.frame.size, CGSize(width: 20, height: 12),
                       "the layout box scales with the corners, so `basis.width == size.width` still holds")
        XCTAssertEqual(text.recipe.typography.pointSize, 24, accuracy: 1e-9,
                       "and the type scales with the box, which is what makes the glyphs bigger")

        guard let fillAfter = vector.elements.compactMap(\.fill).first?.cgPath?.boundingBoxOfPath else {
            return XCTFail("no fill")
        }
        // `CGPath.copy(using:)` works in single precision, so a mapped 16 pt extent comes back as
        // 15.999998 — a fact about CoreGraphics, not about the map.
        XCTAssertEqual(fillAfter.width, fillBefore.width * 2, accuracy: 1e-4, "a fill needs no currency of its own")
        XCTAssertEqual(fillAfter.height, fillBefore.height * 2, accuracy: 1e-4)
    }

    /// A rotation turns a placed image as well as moving it — the other half of the `.image` arm, and
    /// the one a translation-only `mapping` could never have exposed.
    func testARotatedFloatTurnsItsPlacedImage() {
        let (manager, layerIndex, vector) = fixture()
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                                                          size: CGSize(width: 8, height: 8)),
                                           transform: LayerTransform(position: CGPoint(x: 32, y: 32),
                                                                     scale: 1, rotation: 0.2)))
        select(manager, layerIndex, loop(CGRect(x: 16, y: 16, width: 32, height: 32)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        manager.nudgeVectorFloat(to: turnedBy(manager, .pi / 2))

        guard let image = vector.elements.compactMap(\.image).first else { return XCTFail("no image") }
        XCTAssertEqual(image.transform.rotation, 0.2 + .pi / 2, accuracy: 1e-6,
                       "the photo turns with the box rather than sliding around it upright")
    }

    /// **The float's box offers every handle**, and nothing else pinned the constant on either side
    /// of the change: `grep allowedHandles PaintSoftwareUITests/` returned nothing before this test,
    /// so `[.body]` was silent and so would any regression back to it be.
    func testAFloatBoxOffersEveryHandle() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32)))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 22, width: 40, height: 20)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        XCTAssertEqual(manager.vectorFloat?.frame.allowedHandles, Set(ObjectTransformFrame.Handle.allCases),
                       "a lassoed piece scales and turns like the whole-cel box does")
    }

    /// **A scale is a nudge and a rotate is a nudge** — LASSO_MOVE.md §5.2, which the handles do not
    /// change: one gesture, one step, whichever grip the finger was on. Four mixed drags walk back
    /// one at a time and the fifth press gives back the stroke the lasso cut.
    func testAMoveAScaleARotateAndAMoveAreFourStepsAndTheFifthGivesBackTheUnsplitStroke() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        let originalID = vector.elements[0].id
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let stepsAtLift = manager.history.undoStack.count

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 4, dy: 0))
        manager.nudgeVectorFloat(to: scaledBy(manager, 1.5))
        manager.nudgeVectorFloat(to: turnedBy(manager, 0.4))
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 0, dy: 3))
        XCTAssertEqual(manager.history.undoStack.count - stepsAtLift, 4,
                       "one step per gesture, whichever handle it was on")

        for press in 1...3 {
            manager.undo()
            XCTAssertNotNil(manager.vectorFloat, "press \(press) leaves the piece floating")
        }
        manager.undo()
        XCTAssertNil(manager.vectorFloat, "the fourth press ends the float")
        XCTAssertEqual(vector.elements.count, 1, "and gives back one stroke, not two halves")
        XCTAssertEqual(vector.elements[0].id, originalID)
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
    }

    // MARK: - The Move menu (stage 2)
    //
    // The bar is shown for **both** kinds of floating piece since 2026-08-22, so every button on it
    // needs a vector arm as well as the raster one it was written for. These are the vector arms and
    // the two decisions inside them: how a fixed-angle rotation composes, and what Reset costs in
    // undo steps.

    /// **Eight presses of Rotate 45° put the piece back exactly where it started** — the same box
    /// angle bit for bit, the same samples, and the same drawing after the bake.
    ///
    /// A test that checked *one* press would see none of what this is about, and neither would one
    /// that checked eight on a straight layer only. Two separate roundings have to be handled, and
    /// each is watched failing here by a layer rotation chosen to expose it:
    ///
    ///  * **on the straight layer**, the running sum of eight `π/4`s is exactly `2 * .pi`, and `2π`
    ///    is not `0`. Watched failing with `truncatingRemainder` removed from
    ///    `FixedAngleRotation.stepped`: *XCTAssertEqual failed: ("Optional(6.283185307179586)") is
    ///    not equal to ("Optional(0.0)") — eight eighths is a whole turn*, followed by three moved
    ///    samples and *Composites differ at (45, 28) channel A: got 0, expected 255* — a full turn
    ///    is visible in the pixels, not only in the last bits;
    ///  * **on the layer rotated to 1.1 rad**, the running sum lands *off* the eighth-turn grid, and
    ///    the fold cannot save it. 1.1 is not a special number — a sweep of 200 000 lift angles found
    ///    13% of the reachable range behaves this way — it is simply one this suite can name. Watched
    ///    failing with the grid snap removed and the fold kept: *("Optional(1.1)") is not equal to
    ///    ("Optional(1.100000000000001)")*.
    ///
    /// The samples are compared bit-exactly on the straight layer and to 1e-9 on the rotated one, for
    /// `testAZeroDeltaNudgeChangesNoSampleAndNoPixelOnATransformedLayer`'s reason: a zero-delta map on
    /// a transformed layer is a `base ∘ base⁻¹` round trip, which is exactly the identity only when
    /// `base` is.
    func testEightPressesOfRotate45LandTheFloatExactlyWhereItStarted() {
        for layerRotation in [CGFloat(0), 1.1] {
            let (manager, layerIndex, vector) = fixture()
            let layerTransform = CGAffineTransform(rotationAngle: layerRotation)
            vector.setTransform(layerTransform)
            vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 30), size: 5))
            vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 24, y: 34, width: 10, height: 5),
                                                          transform: nil),
                                             color: CodableColor(red: 0, green: 0.5, blue: 1, alpha: 1),
                                             opacity: 1))
            let pixelsBefore = cgImage(vector)
            let note = "layer at \(layerRotation) rad"

            // The loop is canvas space and the geometry is local, so on the turned layer the two are
            // different quadrilaterals — mapped as a *path*, never as a `CGRect`, whose `applying`
            // answers with a bounding box.
            var mapping = layerTransform
            select(manager, layerIndex, CGPath(rect: CGRect(x: 12, y: 12, width: 40, height: 34),
                                               transform: &mapping))
            XCTAssertTrue(manager.beginVectorLassoMove(), note)
            guard let liftRotation = manager.vectorFloat?.frame.transform.rotation else {
                return XCTFail("no float — \(note)")
            }
            let samplesAtLift = vector.elements.compactMap(\.stroke).map(\.samples)

            for press in 1...8 {
                manager.rotateFloating(eighths: 1)
                XCTAssertNotNil(manager.vectorFloat, "press \(press) must not dismiss the piece — \(note)")
            }

            XCTAssertEqual(manager.vectorFloat?.frame.transform.rotation, liftRotation,
                           "eight eighths is a whole turn, and a whole turn is not a rotation — \(note)")
            let samplesAfter = vector.elements.compactMap(\.stroke).map(\.samples)
            XCTAssertEqual(samplesAtLift.count, samplesAfter.count, note)
            for (before, after) in zip(samplesAtLift, samplesAfter) {
                for (a, b) in zip(before, after) {
                    if layerRotation == 0 {
                        XCTAssertEqual(a.x, b.x, "a whole turn must not move a sample — \(note)")
                        XCTAssertEqual(a.y, b.y, note)
                    } else {
                        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, note)
                        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, note)
                    }
                }
            }
            manager.commitVectorFloatIfNeeded()
            assertPixelsIdentical(cgImage(vector), pixelsBefore,
                                  "the drawing after the bake is the drawing before the lift — \(note)")
        }
    }

    // MARK: - The handle box, and what a fresh lift measures

    /// **The handle box is measured once, at the lift, and no gesture can grow it.**
    ///
    /// `contentSize` is assigned on the **model** in exactly two places — the two lift sites in
    /// `CanvasManager+LassoMove.swift` — and `applyToVectorFloat`, which every drag, every Rotate
    /// press and every Mirror goes through, writes `frame.transform`, `frame.aspect` and `mirror` and
    /// nothing else. (Stage 3b phase 3 added a third construction of an `ObjectTransformFrame`
    /// carrying a size, `fittedFrame(of:at:)`, and it is deliberately not a third *assignment*: it
    /// returns a frame for the overlay to draw and never writes it back, which is exactly what keeps
    /// this test's claim true and worth making — see §5.22.) So there is no path by which turning a piece
    /// re-measures the box it is being turned inside, and the "monotonically over repeated gestures"
    /// this file's own callers were warned about could not happen even in principle. Inflation needs
    /// a **fresh lift** — see
    /// `testARotateBakeAndReliftInflatesTheBoxAndTheRoundTripDeflatesItAgain`.
    ///
    /// Both lifts, because both reach the same float through the same `localBounds(of:)`.
    /// `testEightPressesOfRotate45LandTheFloatExactlyWhereItStarted` pins a whole turn inside one
    /// lift as exact for the *geometry*; this is the same lift's answer for the *handles*.
    func testTheBoxDoesNotInflateWithinOneLift() {
        for kind in LiftKind.allCases {
            let (manager, layerIndex, vector) = fixture()
            vector.addStroke(stroke(from: CGPoint(x: 28, y: 20), to: CGPoint(x: 44, y: 44), size: 4))
            XCTAssertTrue(lift(kind, manager, layerIndex), "\(kind.rawValue): nothing lifted")
            guard let atLift = manager.vectorFloat?.frame.contentSize else {
                return XCTFail("no float — \(kind.rawValue)")
            }

            manager.rotateFloating(eighths: 1)          // +45°
            XCTAssertEqual(manager.vectorFloat?.frame.contentSize, atLift,
                           "\(kind.rawValue): a rotation is not a re-measurement")
            manager.rotateFloating(eighths: -1)         // and −45° back
            XCTAssertEqual(manager.vectorFloat?.frame.contentSize, atLift,
                           "\(kind.rawValue): and coming back does not grow it either")
        }
    }

    /// **A fresh lift of already-tilted ink measures a bigger box — and an exactly cancelling round
    /// trip gives the small one back.** The half of "the Move box inflates" that is true and the half
    /// that is not, both stated as numbers rather than as a direction.
    ///
    /// The box is `localBounds(of:)`: the AABB of the stroke's **samples**, padded by `stampRadius`
    /// *afterwards*. The padding is therefore re-applied in the axis-aligned frame at every lift and
    /// is never carried round with the ink — which is why the tilted lift is not the 84.85 pt you get
    /// by rotating the first box. A spine 80 pt long under a 20 pt brush (radius 10) lifts as
    /// 80 + 2×10 by 0 + 2×10 = **100 × 20**; turned 45° that spine spans 80/√2 = 56.57 on each axis
    /// and is padded again, so the second lift measures **76.57 × 76.57**. The 8.28 pt shortfall
    /// against 84.85 is exactly 2·radius·(√2 − 1) — the padding a rotating box would have carried
    /// diagonally and this one does not. Area still nearly triples, which is the real complaint.
    ///
    /// **And it is not monotonic.** Nothing feeds the box back into the geometry, so rotating −45°
    /// and baking puts every sample back where it started and the third lift measures 100 × 20 again.
    /// The box tracks the tilt of the ink in both directions; it does not ratchet.
    ///
    /// Whole-cel rather than lasso only because it needs no loop, and the bar is deliberately longer
    /// than the 64 pt canvas: this measures geometry and `localBounds` never rasterizes.
    func testARotateBakeAndReliftInflatesTheBoxAndTheRoundTripDeflatesItAgain() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: -8, y: 32), to: CGPoint(x: 72, y: 32), size: 20))

        func liftAndMeasure() -> CGSize {
            XCTAssertTrue(manager.beginVectorWholeCelMove(), "the cel must lift")
            return manager.vectorFloat?.frame.contentSize ?? .zero
        }

        let first = liftAndMeasure()
        XCTAssertEqual(first.width, 100, accuracy: 1e-6, "spine 80 plus 2 × radius 10 — measured \(first)")
        XCTAssertEqual(first.height, 20, accuracy: 1e-6, "spine 0 plus 2 × radius 10 — measured \(first)")

        manager.rotateFloating(eighths: 1)
        manager.commitVectorFloatIfNeeded()

        let tilted = liftAndMeasure()
        let tiltedSide = CGFloat(80 / 2.0.squareRoot() + 20)   // 76.5685…, not 120/√2 = 84.8528…
        XCTAssertEqual(tilted.width, tiltedSide, accuracy: 1e-4,
                       "the tilted lift measured \(tilted) against \(first) at the first lift")
        XCTAssertEqual(tilted.height, tiltedSide, accuracy: 1e-4, "and it is square: \(tilted)")
        XCTAssertGreaterThan(tilted.width * tilted.height, first.width * first.height,
                             "\(tilted) must enclose more than \(first) — that is the whole inflation")

        manager.rotateFloating(eighths: -1)
        manager.commitVectorFloatIfNeeded()

        let back = liftAndMeasure()
        XCTAssertEqual(back.width, first.width, accuracy: 1e-6,
                       "an exact round trip deflates it again: \(first) → \(tilted) → \(back)")
        XCTAssertEqual(back.height, first.height, accuracy: 1e-6,
                       "an exact round trip deflates it again: \(first) → \(tilted) → \(back)")
        manager.commitVectorFloatIfNeeded()
    }

    /// The raster piece takes the identical arithmetic, so the two Move tools turn the same way — and
    /// four presses of Rotate 90° close the loop for the same reason eight of 45° do.
    func testEightPressesOfRotate45AndFourOfRotate90CloseTheLoopOnARasterPiece() {
        for (eighths, presses) in [(1, 8), (2, 4), (-1, 8), (-2, 4)] {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(.black, rect: CGRect(x: 10, y: 10, width: 20, height: 14)))
            manager.beginMove()
            guard let lift = manager.floatingPiece?.liftTransform else { return XCTFail("nothing lifted") }

            for _ in 1...presses { manager.rotateFloating(eighths: eighths) }

            XCTAssertEqual(manager.floatingPiece?.transform.rotation, lift.rotation,
                           "\(presses) × \(eighths) eighths is a whole turn")
            XCTAssertEqual(manager.floatingPiece?.transform, lift,
                           "and a whole turn leaves the whole pose alone, not only the angle")
        }
    }

    /// **Fixed-angle rotation composes onto the box's current angle; it does not re-derive from the
    /// pick-up state.** Turning the knob by hand and then pressing 45° adds 45° to the hand-turn —
    /// re-deriving would silently throw the hand-turn away, which is the behaviour this pins against.
    func testRotate45AddsToAFreehandTurnRatherThanReplacingIt() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 22, width: 40, height: 20)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let lift = manager.vectorFloat?.frame.transform.rotation else { return XCTFail("no float") }

        manager.nudgeVectorFloat(to: turnedBy(manager, 0.3))
        manager.rotateFloating(eighths: 1)

        XCTAssertEqual(manager.vectorFloat?.frame.transform.rotation ?? 0, lift + 0.3 + .pi / 4,
                       accuracy: 1e-9,
                       "the button turns the piece from where the artist left it")
    }

    /// **Reset snaps the piece back to exactly where it was picked up, and costs one undo step.**
    ///
    /// The step count is the decision: LASSO_MOVE.md §5's settled rule is one step per nudge, and
    /// Reset is one thing the artist did, so one press of Undo puts the piece back where it was
    /// *before* the Reset. It is not a shortcut for "undo every nudge" — that would spend an unbounded
    /// number of history steps on one tap and, worse, the first nudge's step is the one that un-does
    /// the split, so it would end the float and put the artist back before they pressed Move.
    ///
    /// Watched failing with `resetFloating`'s vector arm passing `mirror: float.mirror` instead of
    /// `.identity`: *the mirror is part of the pose Reset puts back* — the piece landed at the right
    /// place still facing backwards.
    func testResetPutsTheLassoedPieceBackWhereItWasPickedUpInOneUndoableStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 22), to: CGPoint(x: 42, y: 30), size: 5))
        vector.addStroke(stroke(from: CGPoint(x: 22, y: 38), to: CGPoint(x: 30, y: 40), size: 3))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 14, width: 40, height: 34)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let lift = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        let samplesAtLift = vector.elements.compactMap(\.stroke).map(\.samples)
        XCTAssertFalse(manager.canResetFloating, "nothing has moved, so there is nothing to put back")

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 9, dy: -5))
        manager.nudgeVectorFloat(to: scaledBy(manager, 1.7))
        manager.rotateFloating(eighths: 1)
        manager.mirrorFloating(horizontal: true)
        XCTAssertTrue(manager.canResetFloating)
        let poseBeforeReset = manager.vectorFloat?.frame.transform
        let stepsBeforeReset = manager.history.undoStack.count

        manager.resetFloating()

        XCTAssertEqual(manager.history.undoStack.count - stepsBeforeReset, 1, "one tap, one step")
        XCTAssertEqual(manager.vectorFloat?.frame.transform, lift)
        XCTAssertEqual(manager.vectorFloat?.mirror, CGAffineTransform.identity, "the mirror is part of the pose it puts back")
        let samplesAfterReset = vector.elements.compactMap(\.stroke).map(\.samples)
        for (before, after) in zip(samplesAtLift, samplesAfterReset) {
            for (a, b) in zip(before, after) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-6, "back to the pick-up geometry, not near it")
                XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
            }
        }
        XCTAssertFalse(manager.canResetFloating, "and there is nothing left to reset")

        manager.undo()
        XCTAssertEqual(manager.vectorFloat?.frame.transform, poseBeforeReset,
                       "one undo takes back the Reset, not the whole move")
        XCTAssertNotNil(manager.vectorFloat, "and leaves the piece floating, as every other step does")
    }

    /// Reset on a raster piece is the same snap-back and records nothing, because **nothing** about a
    /// raster Move's in-flight transform is on the undo stack — the whole move is one step, taken at
    /// the bake. One Undo afterwards still reverts the move, Reset or no Reset.
    func testResetOnARasterPieceSnapsBackAndAddsNoHistoryStep() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 10, y: 10, width: 20, height: 14)))
        manager.beginMove()
        guard let lift = manager.floatingPiece?.liftTransform else { return XCTFail("nothing lifted") }
        XCTAssertFalse(manager.canResetFloating)
        let stepsAtLift = manager.history.undoStack.count

        var dragged = lift
        dragged.position = CGPoint(x: lift.position.x + 12, y: lift.position.y + 3)
        dragged.scaleX = 1.6
        dragged.scaleY = 1.6
        manager.updateFloatingPose(transform: dragged, distortQuad: nil)
        manager.mirrorFloating(horizontal: true)
        XCTAssertTrue(manager.canResetFloating)

        manager.resetFloating()

        XCTAssertEqual(manager.floatingPiece?.transform, lift, "position, scale, rotation and the flip")
        XCTAssertEqual(manager.history.undoStack.count, stepsAtLift,
                       "a raster move puts one step on the stack, at the bake — Reset is not a second one")
    }

    /// **Mirror flips a lassoed piece about its own centre, and pressing it twice is not an edit.**
    ///
    /// A reflection is the one pose `LayerTransform` cannot hold — position, one scale, one rotation,
    /// no flip — so it rides as `VectorFloat.mirror`, folded in front of the map every nudge already
    /// applies. That is what makes it absolute-from-the-lift like everything else, which the second
    /// half of this test is about: the flip has to survive a later drag rather than being re-applied
    /// or lost.
    ///
    /// Watched failing with `mirror` left out of `applyToVectorFloat`'s `localDelta` (the map built
    /// from the box alone): *XCTAssertEqual failed: ("20.0") is not equal to ("44.0")* — the button
    /// changed the stored flag and not one sample.
    func testMirrorFlipsALassoedPieceAboutItsOwnCentreAndSurvivesALaterDrag() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 28), size: 4))
        let pixelsBefore = cgImage(vector)
        select(manager, layerIndex, loop(CGRect(x: 12, y: 12, width: 40, height: 26)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let float = manager.vectorFloat else { return XCTFail("no float") }
        let pivot = float.pivot

        manager.mirrorFloating(horizontal: true)

        guard let mirrored = vector.elements.compactMap(\.stroke).first?.samples else { return XCTFail("no stroke") }
        XCTAssertEqual(mirrored.first?.x ?? 0, 2 * pivot.x - 20, accuracy: 1e-6,
                       "every sample reflects across the piece's own vertical centre line")
        XCTAssertEqual(mirrored.last?.x ?? 0, 2 * pivot.x - 44, accuracy: 1e-6)
        XCTAssertEqual(mirrored.first?.y ?? 0, 20, accuracy: 1e-6, "and a horizontal mirror leaves y alone")

        // The flip must ride the *next* drag rather than being undone by it: the nudge re-derives from
        // the lift geometry, so a mirror the map does not carry would evaporate here.
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 6, dy: 0))
        guard let after = vector.elements.compactMap(\.stroke).first?.samples else { return XCTFail("no stroke") }
        XCTAssertEqual(after.first?.x ?? 0, 2 * pivot.x - 20 + 6, accuracy: 1e-6,
                       "the piece is still mirrored, and now six points along")

        // Back the other way, and back where it was: two mirrors and a drag home are not an edit.
        manager.mirrorFloating(horizontal: true)
        manager.nudgeVectorFloat(to: float.frame.transform)
        XCTAssertEqual(manager.vectorFloat?.mirror, CGAffineTransform.identity, "two presses cancel")
        manager.commitVectorFloatIfNeeded()
        assertPixelsIdentical(cgImage(vector), pixelsBefore,
                              "a mirror and a mirror back must change no pixel")
    }

    /// Both mirrors together are a half-turn, which is the one composition that has to come out right
    /// for the two buttons to be independent of the order they are pressed in.
    func testMirroringBothWaysIsAHalfTurnAboutThePiecesCentre() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 28), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 12, width: 40, height: 26)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let pivot = manager.vectorFloat?.pivot else { return XCTFail("no float") }

        manager.mirrorFloating(horizontal: true)
        manager.mirrorFloating(horizontal: false)

        guard let samples = vector.elements.compactMap(\.stroke).first?.samples else { return XCTFail("no stroke") }
        XCTAssertEqual(samples.first?.x ?? 0, 2 * pivot.x - 20, accuracy: 1e-6)
        XCTAssertEqual(samples.first?.y ?? 0, 2 * pivot.y - 20, accuracy: 1e-6,
                       "H then V is a point reflection, not a second horizontal flip")
    }

    /// **A piece carrying a stroke *and* a photo mirrors as one thing, and mirroring back is the
    /// drawing that was lifted.**
    ///
    /// This test used to assert the opposite — that Mirror refused, out loud, on any piece holding a
    /// placed image, because the image's whole placement was a `LayerTransform` with no flip in it and
    /// `theta` would have read a plane turned over as an *angle*, coming back a half turn instead of a
    /// mirror. §3 stage 3c gave the image a stored `mirrored` bit and the refusal went with it (as did
    /// `mirrorUnavailableReason` itself, which no kind could answer any more).
    ///
    /// **The mixed piece is what this keeps**, rather than the photo alone, which
    /// `PlacedImageShapeLogicTests` covers: the stroke reflects through the map point for point and the
    /// photo through a decomposed pose, and the two have to agree about the axis or the drawing comes
    /// apart at the seam.
    func testMirroringAPieceCarryingAStrokeAndAPhotoFlipsBothTogether() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                           rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                           size: CGSize(width: 6, height: 6)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 34),
                                                                     scale: 1, rotation: 0)))
        let pixelsBefore = cgImage(vector)
        select(manager, layerIndex, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
        XCTAssertTrue(manager.beginVectorLassoMove(), "the lift should have caught both")
        guard let pivot = manager.vectorFloat?.pivot else { return XCTFail("no float") }
        let stepsBefore = manager.history.undoStack.count

        manager.mirrorFloating(horizontal: true)

        guard let stroke = vector.elements.compactMap(\.stroke).first?.samples,
              let photo = vector.elements.compactMap(\.image).first
        else { return XCTFail("both kinds survive the mirror") }
        XCTAssertEqual(stroke.first?.x ?? 0, 2 * pivot.x - 26, accuracy: 1e-6,
                       "the stroke reflects across the piece's own vertical centre line")
        XCTAssertTrue(photo.mirrored, "and the photo takes the same reflection as a stored bit")
        XCTAssertEqual(photo.transform.position.x, 2 * pivot.x - 30, accuracy: 1e-6,
                       "about the same centre line, so the two do not come apart")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1,
                       "a tap of Mirror is one thing the artist did — §5.5")

        manager.mirrorFloating(horizontal: true)
        manager.commitVectorFloatIfNeeded()
        assertPixelsIdentical(cgImage(vector), pixelsBefore,
                              "a mirror and a mirror back must change no pixel, photo included")
    }

    /// **Mirror reflects the rendered glyphs, and mirroring back is the drawing that was lifted.**
    ///
    /// The owner's ruling of 2026-08-27, verbatim in LASSO_MOVE.md §5.18: the text reads backwards, as
    /// in a real mirror; it is *not* re-laid-out right-to-left.
    ///
    /// **The load-bearing assertion is the sign of the determinant**, and nothing else here can stand
    /// in for it. A frame whose corners had been rotated a half turn instead of reflected would put
    /// every corner in a plausible place, pass any "did the box move" check, and draw the type the
    /// right way round — the exact failure `mapping`'s `.image` arm still asserts against. A negative
    /// determinant on `frame.affineTransform` is the one number that says the plane was turned over,
    /// and every path that draws text concatenates that matrix.
    func testMirroringALassoedTextBoxReflectsTheGlyphsAndMirroringBackIsPixelIdentical() throws {
        let (manager, layerIndex, vector) = fixture()
        var recipe = TextRecipe(string: "Fj")
        recipe.typography.pointSize = 16
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 22, y: 22),
                                                             size: CGSize(width: 20, height: 18))))
        let pixelsBefore = cgImage(vector)
        let before = try XCTUnwrap(vector.elements.compactMap(\.text).first)
        let determinantBefore = determinant(try XCTUnwrap(before.frame.affineTransform))
        XCTAssertGreaterThan(determinantBefore, 0, "fixture precondition: an ordinary, unreflected box")

        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 44, height: 44)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        manager.mirrorFloating(horizontal: true)

        let mirrored = try XCTUnwrap(vector.elements.compactMap(\.text).first)
        let transform = try XCTUnwrap(mirrored.frame.affineTransform,
                                      "a reflected parallelogram still has an affine map; "
                                      + "`affineTransform` guards `abs(det) > 1e-9`, not `det > 0`")
        XCTAssertLessThan(determinant(transform), 0,
                          "the glyphs are reflected — a rotation would leave this positive")
        XCTAssertEqual(mirrored.frame.size, before.frame.size,
                       "a mirror is not a resize: the layout box is untouched, so the words and the "
                       + "line breaks are the ones CoreText already chose")
        XCTAssertEqual(mirrored.recipe.typography.pointSize, before.recipe.typography.pointSize,
                       accuracy: 1e-9, "and the type is the same size, read backwards")

        manager.mirrorFloating(horizontal: true)
        manager.commitVectorFloatIfNeeded()
        assertPixelsIdentical(cgImage(vector), pixelsBefore,
                              "mirror and mirror back must be exactly the original")
    }

    /// A mirror is a nudge: one undo step, the box left standing, and the mirror itself restored — the
    /// half of the pose the box transform cannot carry, and so the half a step that only restored
    /// `frame.transform` would silently drop.
    func testUndoingAMirrorRestoresTheFlipAndLeavesThePieceFloating() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 28), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 12, width: 40, height: 26)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        // A drag first, so the mirror is not the *first* nudge — undoing that one deliberately ends
        // the float and gives back the unsplit stroke, which is a different rule being tested above.
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 5, dy: 0))
        let samplesAfterDrag = vector.elements.compactMap(\.stroke).map(\.samples)
        let stepsAfterDrag = manager.history.undoStack.count

        manager.mirrorFloating(horizontal: true)
        XCTAssertEqual(manager.history.undoStack.count - stepsAfterDrag, 1, "one press, one step")
        XCTAssertNotEqual(manager.vectorFloat?.mirror, CGAffineTransform.identity)

        manager.undo()

        XCTAssertNotNil(manager.vectorFloat, "the piece is still in the artist's hand")
        XCTAssertEqual(manager.vectorFloat?.mirror, CGAffineTransform.identity, "and facing the way it was")
        let samplesAfterUndo = vector.elements.compactMap(\.stroke).map(\.samples)
        for (before, after) in zip(samplesAfterDrag, samplesAfterUndo) {
            for (a, b) in zip(before, after) { XCTAssertEqual(a.x, b.x, accuracy: 1e-6) }
        }

        manager.redo()
        XCTAssertNotEqual(manager.vectorFloat?.mirror, CGAffineTransform.identity, "and redo puts the flip back")
    }

    /// The Move bar's Done button settles **whichever** kind is floating. It used to call
    /// `commitFloatingPieceIfNeeded()` alone, which is the raster piece — on a vector layer that is a
    /// button that returns false and does nothing.
    func testDoneSettlesEitherKindOfFloatingPiece() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 22, width: 40, height: 20)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertTrue(manager.isAnyPieceFloating, "and the bar is up for it")

        XCTAssertTrue(manager.commitAnyFloatingPiece())

        XCTAssertNil(manager.vectorFloat)
        XCTAssertFalse(manager.isAnyPieceFloating)
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
    }

    /// `warp` is gone from the enum rather than hidden — owner, 2026-08-22: *"Unlike procreate, Warp
    /// will not be a feature (like liquify)."* A hidden case stays in `allCases`, keeps answering
    /// `switch`es and keeps its string wherever the next thing to persist a mode would put it; this is
    /// the assertion that a later tidy-up cannot quietly reinstate it.
    ///
    /// **The second half of this test used to read `isImplemented`, and stage 5 deleted the
    /// property.** Distort is built, so the "not implemented" set is empty by construction and the
    /// honest replacement is that every case is a mode the bar can act on. What a *piece* can be
    /// refused for is `CanvasManager.distortUnavailableReason`, and `DistortLogicTests` pins it.
    func testTheTransformModesAreFreeformUniformAndDistortWithNoWarp() {
        XCTAssertEqual(TransformMode.allCases.map(\.rawValue), ["freeform", "uniform", "distort"])
    }

    // MARK: - Freeform (stage 3a)
    //
    // The Move bar's mode picker was raster-only until this stage, and the caption said why: a
    // lassoed vector piece scaled uniformly whichever segment was lit, because `LayerTransform` holds
    // one scale. It now carries an `ObjectTransformFrame.aspect` beside it, and
    // `VectorCanvas.mapping(_:throughStretch:)` carries that into the geometry.
    //
    // **The ruling these tests encode** (owner, 2026-08-26): one toggle decides whether the ink
    // deforms with the shape, over Freeform and Distort together, **defaulting to ink-keeps-its-
    // shape** — so the dab stays round and the path stretches. The round dab takes the map's own area
    // root, `sqrt(|det|)`, which is what makes Freeform *contain* Uniform instead of contradicting it.

    /// **The path stretches; the ink keeps its shape.**
    ///
    /// A 16 pt horizontal spine with 8 pt of ink, stretched to three times its width and left at its
    /// original height, comes back with a 48 pt spine and ink `sqrt(3)`× thicker — not 3× (that is the
    /// deforming-ink mode, which is the toggle's other half and needs a renderer change) and not 1×
    /// (that is "no scaling", the literal reading of an earlier ruling about *Distort*, where there is
    /// no global scale to read). The three are far enough apart that the tolerance cannot hide which
    /// one shipped: 13.9 pt against 8 and 24.
    ///
    /// Watched failing with `stroke.size *= k` removed from the shared `drawn` arm: *("8.0") is not
    /// equal to ("13.86…")* — the spine spread and the ink did not follow it at all.
    func testAFreeformStretchSpreadsThePathAndKeepsTheInkRound() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 8))
        guard let before = inkBounds(vector) else { return XCTFail("nothing rendered") }

        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let pose = stretched(manager, x: 3, y: 1)
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)

        guard let stroke = vector.elements.compactMap(\.stroke).first else { return XCTFail("no stroke") }
        XCTAssertEqual(stroke.size, 8 * sqrt(3), accuracy: 1e-6,
                       "the round dab takes the map's area root, not one of its two axes")
        XCTAssertEqual(stroke.samples.first?.x ?? 0, 8, accuracy: 1e-6, "and the spine takes the full 3×")
        XCTAssertEqual(stroke.samples.last?.x ?? 0, 56, accuracy: 1e-6)
        XCTAssertEqual(stroke.samples.first?.y ?? 0, 32, accuracy: 1e-6, "with the other axis untouched")

        manager.commitVectorFloatIfNeeded()
        guard let after = inkBounds(vector) else { return XCTFail("nothing rendered") }
        XCTAssertEqual(after.width, 3 * 16 + 8 * sqrt(3), accuracy: 1.5,
                       "48 pt of spine plus a dab's worth of cap at each end")
        XCTAssertEqual(after.height, before.height * sqrt(3), accuracy: 1.5,
                       "and the ink is sqrt(3)× thicker — neither 1× nor 3×")
    }

    /// **Changing only the shape changes no ink weight at all**, and that is arithmetic rather than a
    /// special case: a pose whose `scale` did not move has two axis scales that multiply to one, so
    /// `sqrt(|det|)` is one and `stroke.size` is untouched to the last bit.
    ///
    /// It is the property that makes the rule *symmetric*: a piece squashed to a third of its width
    /// and one stretched to three times it are the same statement about ink weight, so the answer
    /// cannot depend on which way round the artist dragged. (Every nudge maps the **lift**, not the
    /// previous nudge, so the second half below is the mirror-image pose rather than a composition —
    /// that absolute-from-the-lift discipline is `VectorFloat.liftedInside`'s whole point.)
    func testAPureShapeChangeLeavesTheInkWeightAlone() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 8))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let box = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }

        // The box's own scale untouched; only the aspect moves. `axisScales` is then (√3, 1/√3).
        manager.nudgeVectorFloat(to: box, aspect: 3)
        guard let squashed = vector.elements.compactMap(\.stroke).first else { return XCTFail("no stroke") }
        XCTAssertEqual(squashed.size, 8, accuracy: 1e-9, "a shape change is not a size change")
        XCTAssertEqual(squashed.samples.first?.x ?? 0, 32 - 8 * sqrt(3), accuracy: 1e-6,
                       "though the spine really did stretch")

        manager.nudgeVectorFloat(to: box, aspect: 1.0 / 3.0)
        guard let pulled = vector.elements.compactMap(\.stroke).first else { return XCTFail("no stroke") }
        XCTAssertEqual(pulled.size, 8, accuracy: 1e-9, "and the same holds squashed the other way")
    }

    /// **The owner's ruling, 2026-08-26: *"a Freeform stretch survives a switch to Uniform — 3:1 stays
    /// 3:1 and scales from there."*** Read here at the level the artist experiences it: stretch the
    /// piece, then scale it with a Uniform corner drag, and both axes double while the shape holds.
    ///
    /// `nudgeVectorFloat(to:)`'s defaulted `aspect` is what carries it — the move band, the knob, the
    /// Rotate buttons and a Uniform corner all leave the stretch alone because none of them passes one.
    ///
    /// Watched failing with that default changed to a bare `1`: *("1.0") is not equal to ("3.0") —
    /// 3:1 stays 3:1*, and the spine snaps back from 48 to 27.7. That is the whole failure mode the
    /// ruling is about — the artist stretches a piece, scales it, and the stretch silently evaporates.
    func testAUniformScaleAfterAStretchKeepsTheStretch() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 28, y: 32), to: CGPoint(x: 36, y: 32), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 16, y: 22, width: 32, height: 20)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        let pose = stretched(manager, x: 3, y: 1)
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)
        guard let afterStretch = vector.elements.compactMap(\.stroke).first else { return XCTFail("no stroke") }
        let spread = (afterStretch.samples.last?.x ?? 0) - (afterStretch.samples.first?.x ?? 0)
        XCTAssertEqual(spread, 24, accuracy: 1e-6,
                       "fixture precondition: an 8 pt spine really is 3× longer, not sqrt(3)× longer")

        manager.nudgeVectorFloat(to: scaledBy(manager, 2))

        XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 3, accuracy: 1e-6, "3:1 stays 3:1")
        guard let afterScale = vector.elements.compactMap(\.stroke).first else { return XCTFail("no stroke") }
        XCTAssertEqual((afterScale.samples.last?.x ?? 0) - (afterScale.samples.first?.x ?? 0),
                       spread * 2, accuracy: 1e-6, "and scales from there")
        XCTAssertEqual(afterScale.size, afterStretch.size * 2, accuracy: 1e-6,
                       "a Uniform scale still thickens the ink, stretch or no stretch")
    }

    /// **Undo restores the aspect, not only the box transform.** The stretch is the third thing a
    /// `LayerTransform` cannot hold — after position/scale/rotation and before the mirror — so a step
    /// that put back `frame.transform` alone would leave a 3:1 box calling itself square, and the
    /// *next* nudge would map the lift through the wrong pose.
    ///
    /// Watched failing with `frame.aspect = oldAspect` removed from the undo closure: the aspect
    /// stays at 3, and the second assertion below (*the geometry comes back with it*) goes red too,
    /// because the following nudge re-derives from a pose that never existed.
    func testUndoingAFreeformNudgeRestoresTheAspectAndNotOnlyTheBox() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 3, dy: 0))
        guard let box = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        let samplesAfterMove = vector.elements.compactMap(\.stroke).first?.samples.map(\.x) ?? []

        let pose = stretched(manager, x: 3, y: 1)
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)
        XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 3, accuracy: 1e-6, "fixture precondition")

        manager.undo()

        XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 1, accuracy: 1e-9,
                       "the box is square again, not merely back at its old scale")
        XCTAssertEqual(manager.vectorFloat?.frame.transform, box)
        let restored = vector.elements.compactMap(\.stroke).first?.samples.map(\.x) ?? []
        XCTAssertEqual(restored.count, samplesAfterMove.count)
        for (a, b) in zip(restored, samplesAfterMove) {
            XCTAssertEqual(a, b, accuracy: 1e-6, "and the geometry comes back with it")
        }
    }

    /// **Reset puts a stretched piece back square**, and it is *offered* for a piece whose only change
    /// is the stretch — which is the half `canResetFloating` would miss if it compared box transforms
    /// alone, since a pure shape change leaves `frame.transform` exactly where the lift put it.
    ///
    /// Watched failing with the `frame.aspect != 1` clause removed from `canResetFloating`: *Reset has
    /// something to put back* fails first, and `resetFloating`'s own guard then makes the press inert,
    /// so the piece stays stretched with no way back short of Undo.
    func testResetPutsAStretchedPieceBackSquareAndIsOfferedForAStretchAlone() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 6))
        let before = cgImage(vector)
        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let box = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        XCTAssertFalse(manager.canResetFloating, "nothing has happened yet")

        manager.nudgeVectorFloat(to: box, aspect: 3)
        XCTAssertEqual(manager.vectorFloat?.frame.transform, box,
                       "fixture precondition: a pure shape change moves nothing the box can hold")
        XCTAssertTrue(manager.canResetFloating, "Reset has something to put back")

        manager.resetFloating()

        XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 1, accuracy: 1e-9)
        manager.commitVectorFloatIfNeeded()
        assertPixelsIdentical(cgImage(vector), before, "and the drawing is the one that was lifted")
    }

    /// **Freeform is offered on every kind a vector cel can hold**, and the piece with all four in it
    /// stretches as one.
    ///
    /// This test used to be the *refusal*: an image's placement was a `LayerTransform`, one scale and
    /// no second axis, so a piece carrying a photo greyed the picker out with a caption. Text lost the
    /// same refusal on 2026-08-27 (§5.18) because a `TextFrame` already carries four free corners; the
    /// photo lost it on §3 stage 3c, which gave it a stored `aspect` and `stretchAxis` of its own. With
    /// no kind left to refuse, `freeformUnavailableReason` was deleted rather than left answering nil,
    /// and `vectorFloatIsFreeform` is `transformMode == .freeform`.
    ///
    /// **What the stretch does to each kind is elsewhere** — the stroke's `sqrt(|det|)` width in this
    /// file, the text box in `testAStretchedTextBoxDistortsItsLetterformsAndDoesNotReflowTheWords`, the
    /// photo in `PlacedImageShapeLogicTests`. What this one keeps is that a *mixed* piece takes the
    /// mode at all, which is the thing the two deleted properties used to decide.
    func testFreeformIsOfferedOnEveryKindThePieceCanCarry() {
        let (imageManager, imageLayer, imageVector) = fixture()
        imageVector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
        imageVector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                                rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                                size: CGSize(width: 6, height: 6)),
                                                transform: LayerTransform(position: CGPoint(x: 30, y: 34),
                                                                          scale: 1, rotation: 0)))
        select(imageManager, imageLayer, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
        XCTAssertTrue(imageManager.beginVectorLassoMove(), "the lift should have caught both")

        imageManager.setTransformMode(.freeform)
        XCTAssertTrue(imageManager.vectorFloatIsFreeform,
                      "a piece carrying a photo stretches as of stage 3c")
        imageManager.nudgeVectorFloat(to: imageManager.vectorFloat!.frame.transform, aspect: 3)
        XCTAssertEqual(imageVector.elements.compactMap(\.image).first?.aspect ?? 0, 3, accuracy: 1e-6,
                       "and the drag reaches the photo rather than being swallowed")

        // The same predicate answers the same way for what a drawing is actually made of — and, since
        // the ruling, for type as well.
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 26, y: 30, width: 10, height: 5),
                                                      transform: nil),
                                         color: black(), opacity: 1, evenOddFill: false))
        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 12
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 30, y: 34),
                                                             size: CGSize(width: 10, height: 6))))
        select(manager, layerIndex, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.setTransformMode(.freeform)
        XCTAssertTrue(manager.vectorFloatIsFreeform, "strokes, fills and text all stretch")
    }

    /// **A stretched text box distorts its letterforms and does not re-flow.** The owner's ruling of
    /// 2026-08-27, verbatim in LASSO_MOVE.md §5.18: *"Same words, same line breaks, wider or taller
    /// glyphs."*
    ///
    /// **The corners are not what this asserts, and that is the whole point.** A test that only
    /// checked where the four corners landed would pass identically for an implementation that
    /// re-flowed the string into a wider box — same quad, different words on different lines — so it
    /// would not settle the ruling at all. What separates the two is the *layout*: the same number of
    /// lines, carrying the same character ranges. And the third layout below is what stops that from
    /// being vacuous: it is what a re-flow would actually have produced, laid out at the width the box
    /// now covers on the canvas, and it has to come out **different** or the two hypotheses were never
    /// distinguishable on this fixture.
    ///
    /// **Per-line widths are deliberately not asserted, and the reason is a fact about fonts rather
    /// than about this code.** The obvious invariant — each line fills the same fraction of the box it
    /// did — is false on the system face, because SF carries size-dependent tracking: MEASURED, the
    /// first line of this fixture goes from 0.630 of its box at 9 pt to 0.587 at 15.6 pt, a 7% drift
    /// with the line breaks bit-identical. `TextLayoutLogicTests`' header states the rule this falls
    /// under — assert identities, never measured glyph widths — and the line *ranges* are the identity
    /// the ruling is actually about.
    ///
    /// The distortion itself is the other half, and one number carries it: the frame's own map scales
    /// its two axes by different amounts. That is exactly what `mapping(_:throughSimilarity:)` asserts
    /// can never reach *it*, and here it is, held in the corners where it belongs.
    func testAStretchedTextBoxDistortsItsLetterformsAndDoesNotReflowTheWords() throws {
        let (manager, layerIndex, vector) = fixture()
        var recipe = TextRecipe(string: "one two three four five")
        recipe.typography.pointSize = 9
        recipe.typography.tracking = 0
        let box = CGSize(width: 30, height: 22)
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(size: box,
                                                             corners: TextFrame.uprightCorners(origin: CGPoint(x: 16, y: 20),
                                                                                               size: box),
                                                             autoSize: false)))
        let layoutBefore = layout(of: recipe, boxWidth: box.width)
        XCTAssertGreaterThan(layoutBefore.lines.count, 1,
                             "fixture precondition: the string has to wrap, or there are no line "
                             + "breaks for a re-flow to move")

        select(manager, layerIndex, loop(CGRect(x: 8, y: 12, width: 48, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let pose = stretched(manager, x: 3, y: 1)
        XCTAssertNotEqual(pose.aspect, 1, "fixture precondition: this is the stretched arm")

        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)

        let text = try XCTUnwrap(vector.elements.compactMap(\.text).first)
        let layoutAfter = layout(of: text.recipe, boxWidth: text.frame.size.width)

        XCTAssertEqual(layoutAfter.lines.count, layoutBefore.lines.count,
                       "same words on the same number of lines — a re-flow would change this")
        for (before, after) in zip(layoutBefore.lines, layoutAfter.lines) {
            XCTAssertEqual(after.range.location, before.range.location, "and the same words on each")
            XCTAssertEqual(after.range.length, before.range.length)
        }

        // What a re-flow *would* have done: the same type laid out at the width the box now covers on
        // the canvas, which is `sqrt(3)` wider again than the layout box. Fewer lines, different
        // breaks. Without this the two assertions above could both hold on a fixture where nothing
        // could have moved anyway.
        let reflowed = layout(of: text.recipe,
                              boxWidth: try XCTUnwrap(text.frame.basis).width)
        XCTAssertLessThan(reflowed.lines.count, layoutAfter.lines.count,
                          "fixture premise: re-flowing into the stretched width is a visibly different "
                          + "document, so the assertions above are discriminating between two live "
                          + "possibilities rather than restating one")

        // The distortion, as one number: the frame's own map no longer scales its axes alike.
        let map = try XCTUnwrap(text.frame.affineTransform)
        let along = hypot(map.a, map.b), down = hypot(map.c, map.d)
        XCTAssertEqual(along / down, 3, accuracy: 1e-6,
                       "a 3:1 pull leaves a 3:1 residue in the corners, which is what widens the glyphs")
        XCTAssertTrue(text.frame.needsBoxSpaceSizing,
                      "and the frame says so, which is what keeps its grips and its regrow honest")
    }

    /// **Freeform contains Uniform on a text box too** — §5.17's ruling, checked on the kind that
    /// reached Freeform a day after it was made.
    ///
    /// The dispatch in `applyToVectorFloat` is `aspect != 1`, an *exact* comparison, so the two arms
    /// are one ULP apart in the artist's hand: a corner dragged along the box's own diagonal writes
    /// `aspect == 1` and goes through the similarity arm, and the smallest wobble off the diagonal
    /// goes through the stretch arm. If the stretch arm left `size` and `pointSize` alone while the
    /// similarity arm scaled them, the two would draw the same pixels out of documents whose stored
    /// point size differed by `k` — the panel would show a different number on either side of a
    /// boundary the artist cannot see, and `TextLayout.minimumBoxSize`'s floor would move with it.
    ///
    /// Asserted against the mapping functions directly rather than through two drags, because that is
    /// where the property lives: at `aspect == 1` the stretch arm's `sqrt(|det t|)` **is** the
    /// similarity arm's `hypot(t.a, t.b)`, so the two must write the same element.
    func testTheStretchArmReducesToTheSimilarityArmForATextBoxWhenNothingIsStretched() throws {
        var recipe = TextRecipe(string: "one two three")
        recipe.typography.pointSize = 11
        let element = VectorElement.text(VectorTextElement(id: UUID(), recipe: recipe,
                                                           frame: TextFrame(origin: CGPoint(x: 7, y: 13),
                                                                            size: CGSize(width: 26, height: 14))))
        // A similarity with all four parts live — scale, rotation and translation — so nothing can
        // agree by being trivial.
        let similarity = CGAffineTransform(rotationAngle: 0.7)
            .concatenating(CGAffineTransform(scaleX: 2.5, y: 2.5))
            .concatenating(CGAffineTransform(translationX: -3, y: 11))

        let viaSimilarity = try XCTUnwrap(VectorCanvas.mapping(element, throughSimilarity: similarity).text)
        let viaStretch = try XCTUnwrap(VectorCanvas.mapping(element, throughStretch: similarity).text)

        XCTAssertEqual(viaStretch.frame.size.width, viaSimilarity.frame.size.width, accuracy: 1e-9,
                       "the layout box is the same box either way")
        XCTAssertEqual(viaStretch.frame.size.height, viaSimilarity.frame.size.height, accuracy: 1e-9)
        XCTAssertEqual(viaStretch.recipe.typography.pointSize, viaSimilarity.recipe.typography.pointSize,
                       accuracy: 1e-9, "and so is the point size the panel will show on re-open")
        for (a, b) in zip(viaStretch.frame.corners, viaSimilarity.frame.corners) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
        XCTAssertFalse(viaStretch.frame.needsBoxSpaceSizing,
                       "an unstretched result keeps stage 4's own sizing arithmetic, untouched")
    }

    /// **The delayed failure, driven rather than reasoned about.** A stretch that survived the nudge
    /// and then evaporated on the artist's next grip drag — or, worse, on their next *keystroke*, days
    /// later — is the shape of bug this feature could most easily have shipped: `TextFrameDrag` and
    /// `TextFrame.resized(to:)` both read `basis.width` as a layout extent and write it back into
    /// `size`, and a stretched frame is precisely one whose `basis.width != size.width`.
    ///
    /// So: stretch a lassoed text box, commit it, and then do both of the things that would quietly
    /// undo it.
    func testAStretchSurvivesTheNextGripDragAndTheNextAutoSizeRegrow() throws {
        let (manager, layerIndex, vector) = fixture()
        var recipe = TextRecipe(string: "wide")
        recipe.typography.pointSize = 9
        let box = CGSize(width: 26, height: 14)
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(size: box,
                                                             corners: TextFrame.uprightCorners(origin: CGPoint(x: 18, y: 24),
                                                                                               size: box),
                                                             autoSize: true)))
        select(manager, layerIndex, loop(CGRect(x: 10, y: 16, width: 44, height: 32)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let pose = stretched(manager, x: 3, y: 1)
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)
        manager.commitVectorFloatIfNeeded()

        let stretchedFrame = try XCTUnwrap(vector.elements.compactMap(\.text).first).frame
        // A 3:1 pull puts `sqrt(3)` of it in each axis of the corners-to-box ratio and the other
        // `sqrt(3)` in the box itself — the decomposition, read back off the stored document.
        let ratio = try XCTUnwrap(stretchedFrame.basis).width / stretchedFrame.size.width
        XCTAssertEqual(ratio, CGFloat(3).squareRoot(), accuracy: 1e-6,
                       "fixture precondition: the corners carry the residue and the box does not")

        // (1) A sizing grip. The right edge is dragged out to twice the box's canvas width; the box
        // grows and the residue is untouched.
        let drag = try XCTUnwrap(TextFrameDrag(frame: stretchedFrame, handle: .right))
        let basis = try XCTUnwrap(stretchedFrame.basis)
        let pulled = CGPoint(x: basis.origin.x + basis.u.dx * basis.width * 2,
                             y: basis.origin.y + basis.u.dy * basis.width * 2)
        let sized = try XCTUnwrap(drag.clampedFrame(draggedTo: pulled),
                                  "the grip has to answer — a nil here is a grip that does nothing")
        XCTAssertNotEqual(sized.size.width, stretchedFrame.size.width,
                          "the grip actually sized something")
        XCTAssertEqual(try XCTUnwrap(sized.basis).width / sized.size.width, ratio, accuracy: 1e-6,
                       "and the stretch is still 3:1 afterwards")

        // (2) The auto-size regrow, which is what a keystroke into a pristine box runs.
        let regrown = stretchedFrame.resized(to: CGSize(width: stretchedFrame.size.width + 9,
                                                        height: stretchedFrame.size.height))
        XCTAssertEqual(try XCTUnwrap(regrown.basis).width / regrown.size.width, ratio, accuracy: 1e-6,
                       "typing one more character must not snap the box back square")
        XCTAssertEqual(regrown[.topLeft].x, stretchedFrame[.topLeft].x, accuracy: 1e-6,
                       "and it still grows from its top-left")
        XCTAssertEqual(regrown[.topLeft].y, stretchedFrame[.topLeft].y, accuracy: 1e-6)
    }

    /// **A stretched float shows the truth between gestures.**
    ///
    /// The latched preview is a *bitmap* under a Core Animation transform, so a non-uniform one
    /// stretches the ink along with the path — the opposite of what the bake does by ruling. The float
    /// therefore drops its latch at the end of any gesture that changed the aspect, exactly as a
    /// `mayDiverge` float and a mirrored one do: the layer re-renders from real geometry, the artist
    /// sees what they will get, and the next drag's preview is measured from *that* render, so the
    /// approximation is one gesture's worth of stretch and never accumulates.
    ///
    /// A Uniform nudge on the same float is checked in the same test, because the cost must be paid
    /// only by the pose that incurs it: an unstretched float keeps the cheap latched path it has had
    /// since the feature shipped.
    func testAStretchedFloatDropsItsLatchAndAUniformOneDoesNot() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(manager.vectorFloat?.mayDiverge, false, "fixture precondition: ordinary artwork")

        manager.nudgeVectorFloat(to: movedBy(manager, dx: 4, dy: 0))
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, true, "a plain move keeps the cheap path")
        XCTAssertEqual(vector.suppressedElementIDs, manager.vectorFloat?.insideIDs)

        let pose = stretched(manager, x: 3, y: 1)
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect, stretchAxis: 0.8)
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, false,
                       "and a stretch hands the display back to the layer's own render")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)

        // The next drag re-arms it, and against the pose the bitmap will actually be rendered at —
        // all three parts, or the stretch already in the bitmap is applied to it a second time, or
        // applied again along a different axis.
        manager.beginVectorFloatDrag()
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, true)
        XCTAssertEqual(manager.vectorFloat?.latchedAspect ?? 0, manager.vectorFloat?.frame.aspect ?? -1)
        XCTAssertEqual(manager.vectorFloat?.latchedStretchAxis ?? 0,
                       manager.vectorFloat?.frame.stretchAxis ?? -1)
        XCTAssertEqual(manager.vectorFloat?.latchedFrameTransform, manager.vectorFloat?.frame.transform)
    }

    /// A fill is the one kind Freeform is *perfect* on: a `CGPath` carries any affine exactly, so the
    /// stretched chunk is the shape the box drew, to the last coordinate — no width scalar to reason
    /// about and no dab walk to re-phase.
    ///
    /// Watched failing with `axisScales` made to ignore the aspect: *("27.71") is not equal to
    /// ("48.0") — three times as wide*, and the height comes back 13.86 instead of 8, because the
    /// piece scaled uniformly by `sqrt(3)` on both axes instead of stretching on one.
    func testAFillFollowsAFreeformStretchExactly() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 24, y: 28, width: 16, height: 8),
                                                      transform: nil),
                                         color: black(), opacity: 1, evenOddFill: false))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let pivot = manager.vectorFloat?.pivot else { return XCTFail("no float") }

        let pose = stretched(manager, x: 3, y: 1)
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)

        guard let box = vector.elements.compactMap(\.fill).first?.cgPath?.boundingBoxOfPath else {
            return XCTFail("no fill")
        }
        XCTAssertEqual(box.width, 48, accuracy: 1e-3, "three times as wide")
        XCTAssertEqual(box.height, 8, accuracy: 1e-3, "and exactly as tall as it was")
        XCTAssertEqual(box.midX, pivot.x, accuracy: 1e-3, "about the box's own centre")
        XCTAssertEqual(box.midY, pivot.y, accuracy: 1e-3)
    }

    // MARK: - Move with no selection (stage 1 of TODO item (15))

    /// **The reported bug, 2026-08-27, and the reason this whole path moved.**
    ///
    /// The owner, on their iPad: *"After I shrink the entire canvas and put in a line, the line does
    /// not bake properly, and only the part of the line in a box around the original object gets
    /// baked."*
    ///
    /// The mechanism, and it is entirely in `VectorCanvas`: `renderLocalContent` rasterizes the
    /// display list into a context of exactly `size` at the **local** origin, and `render()` applies
    /// `_transform` to that finished bitmap *afterwards* — so the clip happens in local space, before
    /// the transform. `addStroke(canvasSpaceStroke:)` stores `canvasPoint · _transform⁻¹`. So on a
    /// cel shrunk by *k* about the ink's centre *P*, the only canvas region a later stroke can
    /// survive in is the canvas rect scaled by *k* about *P* — a box around the original object,
    /// which is what the owner saw, and not the top-left quadrant a first reading predicts.
    ///
    /// **The `viaTheOldWholeLayerTransform` negative control was removed on purpose, not lost in the
    /// clean-up.** Stage 1 of TODO item (12) kept it — it drove `VectorCanvas.setTransform` directly
    /// to assert the loss, so the positive half could not rot into a vacuous pass — and stage 2/3
    /// retired what it was a control *for*: no writer of `_transform` survives in the app, and the
    /// stored field is baked on decode and written as identity, so the local-space clip is no longer
    /// a state any document or any gesture can reach. A control that drives a mechanism nothing can
    /// enter pins a promise this project has stopped making, and it would have been the one caller
    /// keeping `setTransform` alive for stage 4.
    ///
    /// What replaces it is a **live** control, in the same method: `theShrinkHappened` asserts the
    /// object's own ink really did contract to about 0.3x through the float. That is what the old
    /// half was actually guarding — that the fixture did the shrink at all — and it says so against
    /// the mechanism that ships rather than against the one that was deleted.
    func testInkDrawnAfterAWholeCelShrinkIsNotClippedAway() throws {
        /// Points along the second stroke's own line, spread from one corner of the canvas to the
        /// other. Under the old mechanism only the middle one survives.
        let alongTheLine = [CGPoint(x: 8, y: 8), CGPoint(x: 20, y: 20), CGPoint(x: 32, y: 32),
                            CGPoint(x: 44, y: 44), CGPoint(x: 56, y: 56)]
        func theLine() -> VectorStroke { stroke(from: CGPoint(x: 4, y: 4), to: CGPoint(x: 60, y: 60), size: 3) }
        func theObject() -> VectorStroke { stroke(from: CGPoint(x: 24, y: 24), to: CGPoint(x: 40, y: 40), size: 4) }

        // The control: the same line on a cel nothing has ever moved. Every point above is on it.
        let (_, _, untouched) = fixture()
        untouched.addStroke(canvasSpaceStroke: theLine())
        for point in alongTheLine {
            XCTAssertTrue(isOpaque(untouched, at: point),
                          "fixture precondition: \(point) is on the line on an untouched cel")
        }

        // The fix: a 0.3x shrink through Move with no selection.
        let (manager, _, viaTheFloat) = fixture()
        viaTheFloat.addStroke(theObject())
        let objectBefore = try XCTUnwrap(inkBounds(viaTheFloat), "fixture precondition: the object has ink")
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "Move with no selection lifts the whole cel")
        manager.nudgeVectorFloat(to: scaledBy(manager, 0.3))
        manager.commitVectorFloatIfNeeded()
        XCTAssertTrue(viaTheFloat.transform.isIdentity,
                      "the float moved geometry — nothing may have been written to the layer transform")

        // **The live control.** Without this the positive half below could pass on a fixture that
        // never shrank anything — which is the job the deleted `viaTheOldWholeLayerTransform` half
        // was doing, said against the mechanism that ships. An alpha-scanned box is a couple of
        // points wider than the geometry on each side, so the tolerance is loose on purpose; 0.3x of
        // a 16 pt diagonal is unmistakable at any of it.
        let theShrinkHappened = try XCTUnwrap(inkBounds(viaTheFloat))
        XCTAssertLessThan(theShrinkHappened.width, objectBefore.width * 0.6,
                          "the whole-cel Move must actually have contracted the ink, or the assertions "
                          + "below are about a cel nothing happened to")

        viaTheFloat.addStroke(canvasSpaceStroke: theLine())
        for point in alongTheLine {
            XCTAssertTrue(isOpaque(viaTheFloat, at: point),
                          "every sample of a line drawn after a whole-cel shrink must survive the render; \(point) did not")
        }
        guard let after = inkBounds(viaTheFloat), let control = inkBounds(untouched) else {
            return XCTFail("nothing rendered")
        }
        XCTAssertLessThanOrEqual(after.minX, control.minX + 1.5, "the line reaches as far left as it does untouched")
        XCTAssertGreaterThanOrEqual(after.maxX, control.maxX - 1.5, "…and as far right")
    }

    /// **A whole-cel lift splits nothing.** No path test, no `membershipRuns`, no fresh ids — the
    /// moved set is the identity on the display list.
    ///
    /// This is the pinning test for `liftWholeCel`'s central decision. Implementing "the whole canvas
    /// was lassoed" literally, as a canvas rect through `splitForLassoMove`, would cut every stroke
    /// crossing the canvas edge into two permanent strokes with new ids — and this test is what says
    /// so out loud.
    func testAWholeCelLiftSplitsNothingAndCarriesEveryElement() {
        let (manager, _, vector) = fixture()
        // One stroke crossing the canvas edge and one wholly beyond it: exactly what a literal
        // canvas-rect lasso would cut in half and abandon.
        vector.addStroke(stroke(from: CGPoint(x: -12, y: 30), to: CGPoint(x: 30, y: 30), size: 4))
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 12), size: 4))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 40, y: 40, width: 40, height: 40),
                                                      transform: nil),
                                         color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                                         opacity: 1))
        let idsBefore = vector.elements.map(\.id)

        guard let lifted = vector.liftWholeCel() else { return XCTFail("a non-empty cel must lift") }

        XCTAssertEqual(lifted.elements.map(\.id), idsBefore, "same elements, same ids, same order")
        XCTAssertEqual(lifted.insideIDs, Set(idsBefore), "every element travels")
        XCTAssertEqual(vector.elements.map(\.id), idsBefore, "and the cel itself was not re-written")

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        XCTAssertEqual(vector.elements.map(\.id), idsBefore, "the lift is not a split")
        XCTAssertEqual(manager.vectorFloat?.insideIDs, Set(idsBefore))
        XCTAssertEqual(vector.suppressedElementIDs, Set(idsBefore), "all of it is suppressed while it floats")
    }

    /// **Content outside the canvas travels too**, which is the other half of the decision above: a
    /// literal canvas-rect lasso would leave it behind, and off-canvas content is real here — a
    /// stroke drawn past the edge, or content a previous shrink put out there.
    func testOffCanvasContentTravelsWithAWholeCelMove() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 10), size: 4))
        vector.addStroke(stroke(from: CGPoint(x: -40, y: -30), to: CGPoint(x: -20, y: -30), size: 4))
        let offCanvasID = vector.elements[1].id
        let before = vector.elements[1].stroke?.samples.map(\.x) ?? []
        XCTAssertFalse(before.isEmpty, "fixture precondition")

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        XCTAssertTrue(manager.vectorFloat?.insideIDs.contains(offCanvasID) == true,
                      "content beyond the canvas edge is part of the whole cel and must travel with it")
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 5, dy: 0))
        manager.commitVectorFloatIfNeeded()

        let after = vector.elements.first { $0.id == offCanvasID }?.stroke?.samples.map(\.x) ?? []
        XCTAssertEqual(after.count, before.count, "the off-canvas stroke is still one stroke")
        for (a, b) in zip(before, after) {
            XCTAssertEqual(b - a, 5, accuracy: 1e-6, "and it moved with everything else")
        }
    }

    /// Four nudges are four steps, and the fourth press gives back the pre-lift list — the same
    /// ruling as the lasso's, with the split half of it vacuous because a whole-cel lift cuts nothing.
    func testFourWholeCelNudgesAreFourStepsAndTheFourthGivesBackThePreLiftList() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        let originalID = vector.elements[0].id
        let originalSamples = vector.elements[0].stroke?.samples.map(\.x) ?? []

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        XCTAssertEqual(vector.elements.count, 1, "the lift split nothing")
        let stepsAtLift = manager.history.undoStack.count
        for _ in 1...4 { manager.nudgeVectorFloat(to: movedBy(manager, dx: 4, dy: 0)) }
        XCTAssertEqual(manager.history.undoStack.count - stepsAtLift, 4, "one step per nudge, and no more")

        func travellingX() -> CGFloat? { vector.elements.first?.stroke?.samples.first?.x }
        XCTAssertEqual(travellingX() ?? 0, (originalSamples.first ?? 0) + 16, accuracy: 1e-6)
        manager.undo()
        XCTAssertNotNil(manager.vectorFloat, "the first press leaves the piece floating")
        XCTAssertEqual(travellingX() ?? 0, (originalSamples.first ?? 0) + 12, accuracy: 1e-6)
        manager.undo()
        manager.undo()
        XCTAssertNotNil(manager.vectorFloat, "three presses in, the float is still alive")
        manager.undo()

        XCTAssertNil(manager.vectorFloat, "the fourth press ends the float")
        XCTAssertEqual(vector.elements.count, 1)
        XCTAssertEqual(vector.elements[0].id, originalID, "the very stroke that was there before")
        XCTAssertEqual(vector.elements[0].stroke?.samples.map(\.x) ?? [], originalSamples)
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
        XCTAssertNil(manager.selection, "there was no loop, so there is none to put back")
    }

    /// The bake identity, for the whole-cel lift: a nudge to exactly where the box was lifted changes
    /// no sample and no pixel.
    func testAZeroDeltaWholeCelNudgeChangesNoSampleAndNoPixel() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 22), to: CGPoint(x: 40, y: 22), size: 5))
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 34), to: CGPoint(x: 40, y: 34), size: 5))
        let pixelsBefore = cgImage(vector)

        XCTAssertTrue(manager.beginVectorWholeCelMove())
        guard let float = manager.vectorFloat else { return XCTFail("no float") }
        let samplesBefore = vector.elements.compactMap(\.stroke).map(\.samples)
        manager.nudgeVectorFloat(to: float.frame.transform)
        let samplesAfter = vector.elements.compactMap(\.stroke).map(\.samples)

        XCTAssertEqual(samplesBefore.count, samplesAfter.count)
        for (before, after) in zip(samplesBefore, samplesAfter) {
            XCTAssertEqual(before.count, after.count)
            for (a, b) in zip(before, after) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
                XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
            }
        }
        manager.commitVectorFloatIfNeeded()
        assertPixelsIdentical(cgImage(vector), pixelsBefore)
    }

    /// Move on an empty vector cel does **nothing** — no float, no suppression, no undo step. The
    /// same shape as `testAnEmptyLassoDoesNothingAndLeavesTheLoopOnScreen`, answered in `liftWholeCel`
    /// rather than at the call site so no caller can invent a float with nothing in it.
    func testWholeCelMoveOnAnEmptyVectorCelDoesNothing() {
        let (manager, _, vector) = fixture()
        let stepsBefore = manager.history.undoStack.count

        XCTAssertNil(vector.liftWholeCel(), "an empty cel has nothing to lift")
        XCTAssertFalse(manager.beginVectorWholeCelMove())

        XCTAssertNil(manager.vectorFloat)
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
        XCTAssertTrue(vector.elements.isEmpty)
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore, "and records nothing")
    }

    /// **The whole-cel float hands the canvas back.** `commitAllInteractiveState` settles it — which
    /// the `isVectorTransforming` flag it replaced did *not* do, since nothing in that method ever
    /// cleared the flag — so a paint tool selected after a Move can draw again. That flag is gone
    /// (TODO item (12) stage 2) and this is the property that took over from it.
    ///
    /// The property is `CanvasTouchInputs.activeHostIsInteractive`, restated from `reconcileLayers`'
    /// `shouldInteract`. Asserted rather than driven: the tool-switch call sites are TODO item (16),
    /// being fixed independently, and this test's business is only that the whole-cel move no longer
    /// leaves a latch behind for them to trip over.
    func testAWholeCelMoveIsSettledByCommitAllInteractiveStateAndHandsTheCanvasBack() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10), size: 4))
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        XCTAssertTrue(manager.isAnyPieceFloating)

        manager.commitAllInteractiveState()

        XCTAssertNil(manager.vectorFloat, "the float is settled by the same chokepoint every tool switch goes through")
        XCTAssertFalse(manager.isAnyPieceFloating)
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
        let inputs = CanvasTouchInputs(tool: .pen,
                                       hasVectorFloat: manager.vectorFloat != nil,
                                       activeLayer: .vector)
        XCTAssertTrue(inputs.activeHostIsInteractive,
                      "with a paint tool selected the layer's own stroke recognizer must be live again")
    }

    // MARK: - Keep Full Precision (TODO item (14))

    /// **The Move marks what it wrote, on both arms, and only when the option is on.**
    ///
    /// The site is `applyToVectorFloat`, which is the one function a vector Move writes geometry from
    /// — so this is really asserting that the lasso arm and the whole-cel arm reach the same place,
    /// which is `beginVectorWholeCelMove`'s whole design. A test that drove only the lasso would pass
    /// against a fix applied at the lasso lift and leave Move-with-no-selection storing coarse.
    ///
    /// Also asserts what it must *not* touch: the flag is per stroke, so ink that was never lifted
    /// stays on the grid however many times its neighbours are moved.
    func testAMoveMarksWhatItWroteOnlyWhenKeepFullPrecisionIsOn() {
        for kind in LiftKind.allCases {
            for keepPrecision in [false, true] {
                let (manager, layerIndex, vector) = fixture()
                // Inside the lasso arm's loop (x ≥ 24), and outside it.
                vector.addStroke(stroke(from: CGPoint(x: 30, y: 10), to: CGPoint(x: 50, y: 10)))
                vector.addStroke(stroke(from: CGPoint(x: 4, y: 40), to: CGPoint(x: 16, y: 40)))
                manager.preserveMovePrecision = keepPrecision

                XCTAssertTrue(lift(kind, manager, layerIndex), "\(kind.rawValue): lift")
                manager.nudgeVectorFloat(to: movedBy(manager, dx: 4, dy: 0))
                manager.commitVectorFloatIfNeeded()

                let moved = vector.elements.compactMap(\.stroke)
                    .filter { $0.samples.contains { $0.x > 24 } }
                XCTAssertFalse(moved.isEmpty, "\(kind.rawValue): setup — something travelled")
                for stroke in moved {
                    XCTAssertEqual(stroke.precise, keepPrecision,
                                   "\(kind.rawValue), option \(keepPrecision): a moved stroke's storage mode "
                                   + "must follow the option that was on when it moved")
                }
                if kind == .lasso {
                    let untouched = vector.elements.compactMap(\.stroke)
                        .filter { $0.samples.allSatisfy { $0.x < 24 } }
                    XCTAssertFalse(untouched.isEmpty, "setup — something stayed behind")
                    for stroke in untouched {
                        XCTAssertFalse(stroke.precise,
                                       "ink the lasso left alone is not marked by somebody else's move")
                    }
                }
            }
        }
    }

    /// **Undo gives the flag back with the geometry, because they travel in the same step.**
    ///
    /// This is why the mark is made in `applyToVectorFloat` and not in `commitVectorFloatIfNeeded`:
    /// the commit records nothing (every nudge is already on the stack), so a flag set there would be
    /// a change to the saved document with no step carrying it — undo would return the artist's
    /// geometry and leave the storage mode behind.
    func testUndoingAMoveTakesTheFlagBackWithIt() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 30, y: 10), to: CGPoint(x: 50, y: 10)))
        manager.preserveMovePrecision = true

        XCTAssertTrue(lift(.wholeCel, manager, layerIndex))
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 6, dy: 0))
        manager.commitVectorFloatIfNeeded()
        XCTAssertTrue(vector.elements.compactMap(\.stroke).allSatisfy(\.precise))

        manager.undo()
        XCTAssertTrue(vector.elements.compactMap(\.stroke).allSatisfy { !$0.precise },
                      "the step that put the geometry back put the storage mode back with it")
    }

    /// **The Actions bake: every precise stroke on the canvas, one undo step.**
    ///
    /// "On the canvas" is the owner's own scope — all layers, all cels, not the one the artist is
    /// standing on. So the fixture puts precise strokes on two different layers and leaves an ordinary
    /// one beside them, and the assertion is that one press of Undo restores *all* of it.
    ///
    /// The geometry check is the load-bearing one: clearing the flag without moving the samples would
    /// leave a stroke that writes five bytes a sample and shifts a quarter pixel on the very next
    /// save, which is the silent kind of loss this repo keeps paying for.
    func testTheBakeSnapsEveryPreciseStrokeClearsTheFlagsAndIsOneUndoStep() {
        let (manager, _, vector) = fixture()
        manager.addVectorLayer()
        let secondIndex = manager.currentLayerIndex
        guard let second = manager.layers[secondIndex].cels[0].vector else { return XCTFail("no canvas") }

        /// Deliberately off the quarter-pixel grid, so a bake has somewhere to move it to.
        func offGrid(_ x: CGFloat, _ y: CGFloat) -> VectorSample {
            VectorSample(x: x + 0.13, y: y + 0.07, pressure: 1)
        }
        var precise = VectorStroke(brush: BrushLibrary.hardRound, color: black(), size: 4, opacity: 1,
                                   samples: [offGrid(10, 10), offGrid(20, 12), offGrid(30, 14)])
        precise.lattice = DabLattice(samples: [offGrid(10, 10), offGrid(30, 14)],
                                     parameters: [0, 1], seedID: UUID())
        vector.addStroke(precise.markedPrecise())
        second.addStroke(precise.markedPrecise())
        let ordinary = VectorStroke(brush: BrushLibrary.hardRound, color: black(), size: 4, opacity: 1,
                                    samples: [offGrid(40, 40), offGrid(50, 44)])
        vector.addStroke(ordinary)

        XCTAssertEqual(manager.preciseStrokeCount, 2, "one on each layer, and the ordinary one uncounted")
        let geometryBefore = (vector.strokes + second.strokes).map(\.samples)
        let stepsBefore = manager.history.undoStack.count

        XCTAssertEqual(manager.bakePreciseStrokes(), 2)

        XCTAssertEqual(manager.preciseStrokeCount, 0, "nothing is stored at full precision afterwards")
        XCTAssertTrue((vector.strokes + second.strokes).allSatisfy { $0.lattice?.precise != true },
                      "and neither is any lattice — the invariant holds through the bake too")
        for stroke in vector.strokes + second.strokes where (stroke.samples.first?.x ?? 0) < 35 {
            for sample in stroke.samples + (stroke.lattice?.samples ?? []) {
                XCTAssertEqual(sample.x.truncatingRemainder(dividingBy: PackedSampleRun.quantum), 0,
                               accuracy: 1e-9, "\(sample.x) is not on the quarter-pixel grid")
                XCTAssertEqual(sample.y.truncatingRemainder(dividingBy: PackedSampleRun.quantum), 0,
                               accuracy: 1e-9, "\(sample.y) is not on the quarter-pixel grid")
            }
        }
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1,
                       "one menu tap costs one press of Undo, however many cels it touched")

        manager.undo()
        let geometryAfter = (vector.strokes + second.strokes).map(\.samples)
        XCTAssertEqual(geometryAfter, geometryBefore, "undo restores the pre-bake geometry on every layer")
        XCTAssertEqual(manager.preciseStrokeCount, 2, "…and the flags with it")

        // A second press with nothing to bake must not put a no-op on the stack.
        _ = manager.bakePreciseStrokes()
        let stepsAfterBake = manager.history.undoStack.count
        XCTAssertEqual(manager.bakePreciseStrokes(), 0)
        XCTAssertEqual(manager.history.undoStack.count, stepsAfterBake,
                       "baking nothing records nothing")
    }

    // MARK: - The box-only knob (stage 3b, phase 1)
    //
    // A yellow knob off the bottom edge that turns the *handle box* alone, so an artist who re-lifts
    // ink they previously rotated can hand-fit the straight hull `localBounds(of:)` measures around
    // it. LASSO_MOVE.md §5.19–21 and TODO item (20). The whole feature rests on one claim — the box
    // angle is chrome and never reaches the geometry — and the first test below is that claim.

    /// **A non-zero box angle changes no sample and no pixel.** The highest-value test in this
    /// feature, and the mirror of `testAZeroDeltaNudgeChangesNoSampleAndNoPixelOnATransformedLayer`:
    /// that one pins the map at a zero *delta*, this one pins it against a term that must never be in
    /// the map at all.
    ///
    /// The hazard it catches is a leak into the geometry, and a leak would be immediate and visible —
    /// the lift invariant is `VectorCanvas.affine(from: frame.transform, pivot:) == baseTransform`, so
    /// if `boxAngle` reached `affine(from:pivot:)`, `affine(from:aspect:pivot:)`, `axisScales`, or
    /// `applyToVectorFloat`'s `localDelta`, the piece would jump the instant the knob was touched.
    /// Run on a **transformed** layer for the reference test's reason: `base ∘ base⁻¹` is exactly the
    /// identity only when `base` is, so a spurious rotation has somewhere to hide on a straight layer
    /// and nowhere to hide here.
    ///
    /// **Three moments are checked, and the middle one is the one that earns its keep.** A leak could
    /// enter at the turn itself, at a zero-delta nudge taken *after* the turn (which is what an
    /// artist's next drag re-derives its map from), or at the bake.
    ///
    /// **Watched failing — and not hypothetically.** `87081de` shipped with two lines in
    /// `applyToVectorFloat` folding `frame.boxAngle` into `localDelta`, left behind on disk by a
    /// mutation-testing script and committed by another session before the script could restore it.
    /// Against that binary this test went red at the **zero-nudge** assertion:
    /// *("19.999999999994998") is not equal to ("28.483861775054198") +/- ("1e-09") — after the zero
    /// nudge*, and on the **identity** layer transform at that, followed by
    /// `testEightPressesOfRotate45StayBitExactOnAHandTurnedBox`. Nothing else in the suite noticed.
    ///
    /// **The moment it fired at is the finding.** `turnVectorFloatBox` writes one field and touches
    /// no geometry, so the turn alone is silent *even when the map is poisoned*; it is the next
    /// gesture — any gesture, including one that moves nothing — that re-derives the map and drags
    /// the ink. A test that asserted only "the box turned and nothing moved" would have passed
    /// against a build that jumps the artist's drawing on their very next touch.
    func testANonZeroBoxAngleChangesNoSampleAndNoPixel() {
        for transform in [CGAffineTransform.identity,
                          CGAffineTransform(translationX: 7, y: -3).scaledBy(x: 1.4, y: 1.4),
                          CGAffineTransform(rotationAngle: 0.4).concatenating(
                            CGAffineTransform(translationX: 6, y: 9))] {
            let (manager, layerIndex, vector) = fixture()
            vector.setTransform(transform)
            vector.addStroke(stroke(from: CGPoint(x: 6, y: 22), to: CGPoint(x: 40, y: 22), size: 5))
            vector.addStroke(stroke(from: CGPoint(x: 6, y: 34), to: CGPoint(x: 40, y: 34), size: 5))
            let localLoop = CGRect(x: 20, y: 4, width: 40, height: 50)
            var mapping = transform
            let canvasLoop = CGPath(rect: localLoop, transform: &mapping)
            let pixelsBefore = cgImage(vector)
            select(manager, layerIndex, canvasLoop)
            XCTAssertTrue(manager.beginVectorLassoMove(), "transform \(transform)")
            guard let float = manager.vectorFloat else { return XCTFail("no float") }

            let samplesBefore = vector.elements.compactMap(\.stroke).map(\.samples)

            manager.turnVectorFloatBox(to: 0.9)
            XCTAssertEqual(manager.vectorFloat?.frame.boxAngle ?? 0, 0.9, accuracy: 1e-12,
                           "the box turned — transform \(transform)")
            XCTAssertEqual(manager.vectorFloat?.frame.transform, float.frame.transform,
                           "and the box's own similarity is untouched — transform \(transform)")
            assertSamplesUnmoved(vector, samplesBefore, "after the turn, transform \(transform)")

            // The next thing a real artist does is drag something. A zero-delta drag re-derives the
            // map from the pose the turn left behind, so this is where a leak through `frame` shows.
            manager.nudgeVectorFloat(to: float.frame.transform)
            assertSamplesUnmoved(vector, samplesBefore, "after the zero nudge, transform \(transform)")
            XCTAssertEqual(manager.vectorFloat?.frame.boxAngle ?? 0, 0.9, accuracy: 1e-12,
                           "and a nudge does not straighten the box — transform \(transform)")

            manager.commitVectorFloatIfNeeded()
            assertPixelsIdentical(cgImage(vector), pixelsBefore, "transform \(transform)")
        }
    }

    /// **Turning the box records nothing, and that is a ruling rather than a saving** —
    /// LASSO_MOVE.md §5.21, a stated exception to §5.5's "one turn of a knob is one step".
    ///
    /// The reason is the consequence asserted at the end. Turning the box as the **first** thing
    /// after a lasso lift is the dangerous case: the first nudge's step is the one that also un-does
    /// the split (§5.8), so a box turn that recorded a step would make one press of Undo rejoin the
    /// cut stroke and dismiss the whole float — wildly out of proportion to straightening a box. So
    /// the piece must still be floating, still split, and the artist's Undo must still reach whatever
    /// they did *before* they pressed Move.
    ///
    /// Watched failing with `turnVectorFloatBox` routed through `applyToVectorFloat(transform:
    /// aspect:mirror:)` the way every other box change is: *("3") is not equal to ("2") — turning the
    /// box to 0.3 must cost no step*, then ("4") for the next turn and so on — **one step per turn,
    /// accumulating**, which is the shape of the harm rather than a single off-by-one. It is the only
    /// test in the suite that goes red for it.
    func testTurningTheBoxCostsNoUndoStepAndCannotDismissTheFloat() {
        let (manager, layerIndex, vector) = fixture()
        // One stroke crossing the loop, so the lift really does split something for an undo to rejoin.
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 30), to: CGPoint(x: 60, y: 30), size: 4))
        let stepsAfterDrawing = manager.history.undoStack.count
        select(manager, layerIndex, loop(CGRect(x: 34, y: 10, width: 26, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let elementsAfterSplit = vector.elements.count
        XCTAssertEqual(manager.history.undoStack.count, stepsAfterDrawing,
                       "fixture precondition: the lift itself records nothing")

        for angle in [CGFloat(0.3), 0.9, -1.4, 0] {
            manager.turnVectorFloatBox(to: angle)
            XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, angle)
            XCTAssertEqual(manager.history.undoStack.count, stepsAfterDrawing,
                           "turning the box to \(angle) must cost no step")
        }

        manager.turnVectorFloatBox(to: 0.7)
        XCTAssertNotNil(manager.vectorFloat, "the piece is still floating")
        XCTAssertEqual(vector.elements.count, elementsAfterSplit, "and still split")
        XCTAssertEqual(manager.vectorFloat?.nudges, 0,
                       "a box turn is not a nudge — the next drag is still the one that carries the split")
    }

    /// **Rotate 45° stays bit-exact on a box the artist has turned.** `FixedAngleRotation` steps from
    /// `float.liftFrameTransform.rotation` and re-quantises onto the eighth-turn grid measured from
    /// the lift (§5.15); `boxAngle` is not in that computation and must not become part of it, or the
    /// 13% of lift angles that need the snap would come back a few ulps off after eight presses.
    ///
    /// The same fixture as `testEightPressesOfRotate45LandTheFloatExactlyWhereItStarted`, with a hand
    /// turn added — including the 1.1 rad layer, which is one of the 13%.
    ///
    /// **Watched failing against the real defect `87081de` shipped** — `frame.boxAngle` folded into
    /// `applyToVectorFloat`'s `localDelta` — which is the leak this test catches from the other side:
    /// `rotateFloating` goes through that same map, so eight presses on a turned box no longer close
    /// the loop and the samples come back moved. It went red together with
    /// `testANonZeroBoxAngleChangesNoSampleAndNoPixel` and with nothing else in 1839 tests.
    func testEightPressesOfRotate45StayBitExactOnAHandTurnedBox() {
        for layerRotation in [CGFloat(0), 1.1] {
            let (manager, layerIndex, vector) = fixture()
            let layerTransform = CGAffineTransform(rotationAngle: layerRotation)
            vector.setTransform(layerTransform)
            vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 30), size: 5))
            let pixelsBefore = cgImage(vector)
            let note = "layer at \(layerRotation) rad"

            var mapping = layerTransform
            select(manager, layerIndex, CGPath(rect: CGRect(x: 12, y: 12, width: 40, height: 34),
                                               transform: &mapping))
            XCTAssertTrue(manager.beginVectorLassoMove(), note)
            guard let liftRotation = manager.vectorFloat?.frame.transform.rotation else {
                return XCTFail("no float — \(note)")
            }
            manager.turnVectorFloatBox(to: 0.85)
            let samplesAtLift = vector.elements.compactMap(\.stroke).map(\.samples)

            for press in 1...8 {
                manager.rotateFloating(eighths: 1)
                XCTAssertNotNil(manager.vectorFloat, "press \(press) must not dismiss the piece — \(note)")
            }

            XCTAssertEqual(manager.vectorFloat?.frame.transform.rotation, liftRotation,
                           "eight eighths is a whole turn, hand-turned box or not — \(note)")
            XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, 0.85,
                           "and eight presses left the hand-fit exactly where it was — \(note)")
            let samplesAfter = vector.elements.compactMap(\.stroke).map(\.samples)
            XCTAssertEqual(samplesAtLift.count, samplesAfter.count, note)
            for (before, after) in zip(samplesAtLift, samplesAfter) {
                for (a, b) in zip(before, after) {
                    if layerRotation == 0 {
                        XCTAssertEqual(a.x, b.x, "a whole turn must not move a sample — \(note)")
                        XCTAssertEqual(a.y, b.y, note)
                    } else {
                        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, note)
                        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, note)
                    }
                }
            }
            manager.commitVectorFloatIfNeeded()
            assertPixelsIdentical(cgImage(vector), pixelsBefore, note)
        }
    }

    /// **Freeform is offered at every box angle, on every kind** — phase 2 (LASSO_MOVE.md §5.20). This
    /// test is the phase-1 one turned round: it asserted the caption *"The box is turned. Straighten it
    /// to stretch this piece."* and that `vectorFloatIsFreeform` went false with it, and both are gone
    /// rather than relaxed, because `ObjectTransformDrag.stretched` measures from the *drawn* box and
    /// records the axis it pulled along.
    ///
    /// **The image arm was the last refusal left and §3 stage 3c removed it too**, so the second half
    /// of this test is now positive: a photo on a *turned* box stretches, and the axis the drag was
    /// made about is what lands in the element — the two used to be confusable and now have to agree.
    ///
    /// Uniform, Rotate 45° and Mirror keep working at any box angle, as they did in phase 1: a
    /// uniform drag scales the ratio of two radii about the anchor and a rotate knob measures a swept
    /// angle about the same one, so neither reads a rotation at all.
    func testFreeformIsOfferedAtEveryBoxAngleAndOnEveryKind() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
        select(manager, layerIndex, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.setTransformMode(.freeform)
        XCTAssertTrue(manager.vectorFloatIsFreeform, "a straight box stretches")

        for angle in [CGFloat(0.6), -1.4, CGFloat.pi / 2, 0] {
            manager.turnVectorFloatBox(to: angle)
            XCTAssertTrue(manager.vectorFloatIsFreeform,
                          "a turned box stretches too, as of phase 2 — \(angle)")
        }

        // Uniform, Rotate 45° and Mirror are unaffected, on a turned box as before.
        manager.turnVectorFloatBox(to: 0.6)
        let box = manager.vectorFloat!.frame.transform
        manager.nudgeVectorFloat(to: scaledBy(manager, 2))
        XCTAssertEqual(manager.vectorFloat?.frame.transform.scale ?? 0, box.scale * 2, accuracy: 1e-9,
                       "a uniform scale works at any box angle")
        manager.mirrorFloating(horizontal: true)
        XCTAssertNotNil(manager.vectorFloat, "and so does Mirror")
        manager.rotateFloating(eighths: 1)
        XCTAssertNotNil(manager.vectorFloat)

        // The refusal that used to be left, now asserted as behaviour and still on a turned box, so a
        // stretch made about the visible edge cannot be confused with one made about the ink's own.
        let (imageManager, imageLayer, imageVector) = fixture()
        imageVector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
        imageVector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                                rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                                size: CGSize(width: 6, height: 6)),
                                                transform: LayerTransform(position: CGPoint(x: 30, y: 34),
                                                                          scale: 1, rotation: 0)))
        select(imageManager, imageLayer, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
        XCTAssertTrue(imageManager.beginVectorLassoMove())
        imageManager.turnVectorFloatBox(to: 0.6)
        imageManager.setTransformMode(.freeform)
        XCTAssertTrue(imageManager.vectorFloatIsFreeform, "a photo stretches at a turned box too")

        imageManager.nudgeVectorFloat(to: imageManager.vectorFloat!.frame.transform,
                                      aspect: 2.5, stretchAxis: 0.6)
        guard let photo = imageVector.elements.compactMap(\.image).first else {
            return XCTFail("the photo survives the stretch")
        }
        XCTAssertEqual(photo.aspect, 2.5, accuracy: 1e-6,
                       "the box's shape landed in the element's own stored aspect")
        XCTAssertEqual(photo.stretchAxis, 0.6, accuracy: 1e-6,
                       "and so did the axis it was pulled along — §5.20, in the document this time")
    }

    /// **Reset does not touch the box angle, and a turned box does not by itself offer Reset.**
    ///
    /// This is where §5.16 (*Reset is one undoable step*) meets §5.21 (*turning the box costs no undo
    /// step*), and the resolution is argued on `canResetFloating`. Two harms follow from the other
    /// answer, and this test is both of them:
    ///
    ///   * A box angle that *enabled* Reset would make it pressable on a piece that has not moved, and
    ///     `resetFloating` would then take a zero-delta nudge — which is still a nudge, and on an
    ///     untouched float it is `nudges == 1`, the step that carries the pre-split display list. One
    ///     Undo afterwards would rejoin the cut stroke and dismiss the float.
    ///   * A Reset that *straightened* the box would destroy a hand-fit that no Undo could give back,
    ///     since `registerVectorFloatNudgeUndo` restores the transform, the aspect and the mirror, and
    ///     deliberately not the box angle.
    ///
    /// So Reset answers "put the drawing back where I picked it up", and the box angle is not where
    /// the drawing is. It survives Reset, Undo and Redo alike, and goes when the float goes.
    ///
    /// Watched failing with `boxAngle != 0` added to `canResetFloating` **and** `resetFloating`
    /// zeroing it — the other answer, written out in full. All three harms show at once:
    /// *XCTAssertFalse failed — a turned box is not a moved drawing, and Reset must not spend a step
    /// on it*; then *("Optional(0.0)") is not equal to ("Optional(0.75)") — and the hand-fitted box is
    /// still hand-fitted*; and finally the same on *undo does not restore it*, which is the one that
    /// settles it — the step Reset recorded cannot give the angle back, because §5.21 keeps it off
    /// the stack in both directions.
    func testResetLeavesTheBoxAngleAloneAndABoxAngleAloneDoesNotOfferReset() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 32), to: CGPoint(x: 40, y: 32), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 20, width: 40, height: 24)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertFalse(manager.canResetFloating, "nothing has happened yet")

        manager.turnVectorFloatBox(to: 0.75)
        XCTAssertFalse(manager.canResetFloating,
                       "a turned box is not a moved drawing, and Reset must not spend a step on it")

        // Now move the piece for real, so Reset is legitimately offered, and press it.
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 7, dy: -3))
        XCTAssertTrue(manager.canResetFloating)
        manager.resetFloating()

        XCTAssertEqual(manager.vectorFloat?.frame.transform, manager.vectorFloat?.liftFrameTransform,
                       "the drawing is back where it was picked up")
        XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, 0.75,
                       "and the hand-fitted box is still hand-fitted")

        // Undo and redo of the steps around it leave the box angle alone in both directions — §5.21
        // keeps it off the stack, so neither can carry it.
        manager.undo()
        XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, 0.75, "undo does not restore it")
        manager.redo()
        XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, 0.75, "and redo does not clear it")

        manager.commitVectorFloatIfNeeded()
        XCTAssertNil(manager.vectorFloat, "and it goes with the float it belonged to")
    }

    /// A box turn with nothing floating is inert rather than a crash or a stray write — the guard
    /// every other float operation carries, restated for the one that does not go through
    /// `applyToVectorFloat`.
    func testTurningTheBoxWithNothingFloatingDoesNothing() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 10)))
        let steps = manager.history.undoStack.count
        manager.turnVectorFloatBox(to: 1.2)
        XCTAssertNil(manager.vectorFloat)
        XCTAssertEqual(manager.history.undoStack.count, steps)
    }

    // MARK: - The stretch axis (stage 3b, phase 2)
    //
    // A stretch made about a hand-turned box records the axis it was made about — LASSO_MOVE.md
    // §5.20 — and that recorded axis, not the live `boxAngle`, is what enters the map. The three
    // tests below are the three claims that follow: the ink moves along the edges the artist can
    // *see*, turning the box afterwards still moves nothing, and neither §5.15's Rotate-45
    // exactness nor §5.17's `sqrt(|det|)` ink width notices the extra angle.

    /// **A Freeform stretch on a hand-turned box moves the ink along the box's *visible* axes**, and
    /// the expected sample positions are worked out by hand rather than read back out of the code.
    ///
    /// The box is turned a quarter turn by the yellow knob alone, so the drawing is still upright and
    /// the box's own +x axis points down the screen. Pulling the bottom-right grip three times as far
    /// down triples the box's **width** — and the map that implies is `R(π/2)·diag(3,1)·R(−π/2)`,
    /// which is `diag(1, 3)`: **every sample keeps its x and has its y tripled about the pivot**.
    ///
    /// Phase 1 measured the same finger movement from `start.rotation` — the *ink's* angle, which
    /// here is zero — so it would have read it as a pull along the box's height and stretched the
    /// drawing in the direction the artist did not point. That is what phase 1's caption refused
    /// rather than doing.
    func testAStretchOnAHandTurnedBoxMovesTheInkAlongTheBoxsVisibleAxes() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 22, y: 22), to: CGPoint(x: 42, y: 38), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 12, width: 44, height: 40)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let lifted = manager.vectorFloat else { return XCTFail("no float") }
        let pivot = lifted.pivot
        let before = vector.elements.compactMap(\.stroke).map(\.samples)
        XCTAssertFalse(before.isEmpty, "fixture precondition")

        manager.turnVectorFloatBox(to: .pi / 2)
        guard let frame = manager.vectorFloat?.frame else { return XCTFail("no float") }
        let centre = frame.centre
        let (cw, ch) = (frame.contentSize.width, frame.contentSize.height)
        // The grip's offset from the centre is (+cw/2, +ch/2) in the box's own axes; a quarter turn
        // maps that to canvas (−ch/2, +cw/2), so tripling the box's x means tripling the canvas y.
        let pulled = CGPoint(x: centre.x - ch / 2, y: centre.y + 3 * cw / 2)
        let pose = ObjectTransformDrag(frame: frame, handle: .bottomRight, at: frame.corners[2],
                                       freeform: true).pose(draggedTo: pulled)
        XCTAssertEqual(pose.aspect, 3, accuracy: 1e-9, "the drag read a pull along the box's width")
        XCTAssertEqual(pose.stretchAxis, .pi / 2, accuracy: 1e-12, "and recorded the axis it used")
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect,
                                 stretchAxis: pose.stretchAxis)

        let after = vector.elements.compactMap(\.stroke).map(\.samples)
        XCTAssertEqual(after.count, before.count)
        for (b, a) in zip(before, after) {
            for (was, now) in zip(b, a) {
                XCTAssertEqual(now.x, was.x, accuracy: 1e-6, "canvas x is untouched")
                XCTAssertEqual(now.y, pivot.y + 3 * (was.y - pivot.y), accuracy: 1e-6,
                               "and canvas y is tripled about the pivot")
            }
        }
    }

    /// **Turning the box after a stretch changes no sample and no pixel** — the claim phase 2 rests
    /// on, and the reason `boxAngle` and `stretchAxis` are two fields rather than one.
    ///
    /// LASSO_MOVE.md §5.21 makes a box-only turn free: no undo step, on the argument that it moves no
    /// ink. Reading the *live* box angle in the map instead of the recorded stretch axis would make a
    /// turn of the yellow knob re-aim a stretch the artist had already committed, dragging their
    /// drawing with nothing on the stack to give it back. §5.20's own text discloses that as an
    /// unavoidable consequence; it is not, and this is why.
    ///
    /// **Three moments, and the middle one earns its keep**, exactly as in
    /// `testANonZeroBoxAngleChangesNoSampleAndNoPixel`: a leak could enter at the turn, at the
    /// zero-delta nudge an artist's next drag re-derives its map from, or at the bake. Run on a
    /// **transformed** layer, because `base ∘ base⁻¹` is exactly the identity only when `base` is.
    func testTurningTheBoxAfterAStretchChangesNoSampleAndNoPixel() {
        for transform in [CGAffineTransform.identity,
                          CGAffineTransform(rotationAngle: 0.4).concatenating(
                            CGAffineTransform(translationX: 6, y: 9))] {
            let (manager, layerIndex, vector) = fixture()
            vector.setTransform(transform)
            vector.addStroke(stroke(from: CGPoint(x: 8, y: 22), to: CGPoint(x: 44, y: 30), size: 5))
            var mapping = transform
            let canvasLoop = CGPath(rect: CGRect(x: 4, y: 8, width: 56, height: 44),
                                    transform: &mapping)
            select(manager, layerIndex, canvasLoop)
            XCTAssertTrue(manager.beginVectorLassoMove(), "transform \(transform)")
            guard let frame = manager.vectorFloat?.frame else { return XCTFail("no float") }

            // Stretch it 3:1 about a box the artist had already turned — the pose phase 1 refused.
            manager.turnVectorFloatBox(to: 0.7)
            var stretchedBox = frame.transform
            stretchedBox.scale *= sqrt(3)
            manager.nudgeVectorFloat(to: stretchedBox, aspect: 3, stretchAxis: 0.7)
            XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis ?? 0, 0.7, accuracy: 1e-12,
                           "fixture precondition: the stretch is on the record")

            // From here on the drawing must not move, however the box is turned.
            let samplesAfterStretch = vector.elements.compactMap(\.stroke).map(\.samples)
            let pixelsAfterStretch = cgImage(vector)
            let boxAfterStretch = manager.vectorFloat?.frame.transform

            for angle in [CGFloat(1.9), -0.4, 0] {
                manager.turnVectorFloatBox(to: angle)
                assertSamplesUnmoved(vector, samplesAfterStretch,
                                     "after turning to \(angle), transform \(transform)")
                XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis ?? 0, 0.7, accuracy: 1e-12,
                               "the recorded axis is not the box angle — \(angle)")
                XCTAssertEqual(manager.vectorFloat?.frame.transform, boxAfterStretch,
                               "and the box's own similarity is untouched — \(angle)")
            }

            // The next thing a real artist does is drag something, and a zero-delta drag re-derives
            // the whole map from the pose the turns left behind.
            manager.nudgeVectorFloat(to: stretchedBox)
            assertSamplesUnmoved(vector, samplesAfterStretch,
                                 "after the zero nudge, transform \(transform)")
            XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 3, accuracy: 1e-12,
                           "and the nudge carried the stretch and its axis, not one of the two")
            XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis ?? 0, 0.7, accuracy: 1e-12)

            manager.commitVectorFloatIfNeeded()
            assertPixelsIdentical(cgImage(vector), pixelsAfterStretch, "transform \(transform)")
        }
    }

    /// **§5.15's Rotate-45 exactness and §5.17's `sqrt(|det|)` ink width both survive the extra
    /// angle**, on a piece that is stretched *and* hand-turned — the pose neither ruling was written
    /// against.
    ///
    /// Rotation has determinant 1, so no rotation on either side of the scale can change a stroke's
    /// width; and `FixedAngleRotation` steps from `liftFrameTransform.rotation`, which neither new
    /// angle appears in. Eight presses therefore return the identical matrix and the identical
    /// samples — bit for bit on a straight layer, exactly as with no stretch at all.
    func testEightPressesOfRotate45StayBitExactOnAStretchedHandTurnedBox() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 30), size: 5))
        let widthAtLift = vector.strokes.first?.size ?? 0
        select(manager, layerIndex, loop(CGRect(x: 12, y: 12, width: 40, height: 34)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        guard let frame = manager.vectorFloat?.frame else { return XCTFail("no float") }
        let liftRotation = frame.transform.rotation

        manager.turnVectorFloatBox(to: 0.85)
        var stretchedBox = frame.transform
        stretchedBox.scale *= sqrt(3)
        manager.nudgeVectorFloat(to: stretchedBox, aspect: 3, stretchAxis: 0.85)
        let samplesAfterStretch = vector.elements.compactMap(\.stroke).map(\.samples)

        // §5.17, restated against the new angle: the width follows the map's *area* root, and the
        // area of a 3:1 stretch whose scale is √3 is 3 — whichever axis it was made about.
        XCTAssertEqual(vector.strokes.first?.size ?? 0, widthAtLift * sqrt(3), accuracy: 1e-9,
                       "sqrt(|det|) is sqrt(3·1)·1 — the stretch axis has determinant 1")

        for press in 1...8 {
            manager.rotateFloating(eighths: 1)
            XCTAssertNotNil(manager.vectorFloat, "press \(press) must not dismiss the piece")
        }

        XCTAssertEqual(manager.vectorFloat?.frame.transform.rotation, liftRotation,
                       "eight eighths is a whole turn, stretched and hand-turned or not")
        XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis, 0.85, "and the axis rode through it")
        XCTAssertEqual(manager.vectorFloat?.frame.aspect, 3)
        XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, 0.85)
        XCTAssertEqual(vector.strokes.first?.size ?? 0, widthAtLift * sqrt(3), accuracy: 1e-12,
                       "and a whole turn changed no width")
        let after = vector.elements.compactMap(\.stroke).map(\.samples)
        XCTAssertEqual(after.count, samplesAfterStretch.count)
        for (before, now) in zip(samplesAfterStretch, after) {
            for (a, b) in zip(before, now) {
                XCTAssertEqual(a.x, b.x, "a whole turn must not move a sample")
                XCTAssertEqual(a.y, b.y)
            }
        }
    }

    /// **Undo restores the stretch axis, not only the aspect** — the fourth thing a nudge changes,
    /// and the one a step that forgot it would leave pointing the wrong way. The harm is specific: an
    /// undo that gave back `aspect == 3` with the axis reset to 0 would put the piece back at the
    /// right *proportions* along the wrong direction, which is a document the artist never made.
    ///
    /// Also the lift invariant with both new angles non-zero: the map is `affine(from:aspect:
    /// stretchAxis:pivot:)` and at `aspect == 1` the axis is a no-op, so the piece is back where it
    /// was picked up and Reset agrees.
    func testUndoRestoresTheStretchAxisAndResetClearsIt() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 22, y: 26), to: CGPoint(x: 42, y: 26), size: 4))
        select(manager, layerIndex, loop(CGRect(x: 12, y: 14, width: 44, height: 32)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        let samplesAtLift = vector.elements.compactMap(\.stroke).map(\.samples)
        // One ordinary nudge first, so the stretch is the *second* step: the first nudge's step is
        // the one that also un-does the split (§5.8), and undoing that dismisses the float.
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 3, dy: 0))
        let samplesAfterMove = vector.elements.compactMap(\.stroke).map(\.samples)
        guard let frame = manager.vectorFloat?.frame else { return XCTFail("no float") }

        manager.turnVectorFloatBox(to: 1.1)
        var stretchedBox = frame.transform
        stretchedBox.scale *= sqrt(3)
        manager.nudgeVectorFloat(to: stretchedBox, aspect: 3, stretchAxis: 1.1)
        XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis, 1.1)

        manager.undo()
        XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 1, accuracy: 1e-12,
                       "undo gives the shape back")
        XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis ?? -1, 0, accuracy: 1e-12,
                       "and the axis it was made about with it")
        assertSamplesUnmoved(vector, samplesAfterMove, "after the undo")
        manager.redo()
        XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis ?? 0, 1.1, accuracy: 1e-12,
                       "and redo puts both back")

        // Reset writes the lift's pose, which is aspect 1 and axis 0 — and leaves the hand-fitted box
        // angle alone, §5.21 as before.
        XCTAssertTrue(manager.canResetFloating)
        manager.resetFloating()
        XCTAssertEqual(manager.vectorFloat?.frame.aspect ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(manager.vectorFloat?.frame.boxAngle, 1.1, "the hand fit is not the drawing")
        assertSamplesUnmoved(vector, samplesAtLift, "after the reset")
    }

    /// Every sample of every stroke is where it was. The assertion
    /// `testANonZeroBoxAngleChangesNoSampleAndNoPixel` makes three times.
    private func assertSamplesUnmoved(_ vector: VectorCanvas, _ before: [[VectorSample]],
                                      _ note: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let after = vector.elements.compactMap(\.stroke).map(\.samples)
        XCTAssertEqual(before.count, after.count, note, file: file, line: line)
        for (b, a) in zip(before, after) {
            XCTAssertEqual(b.count, a.count, note, file: file, line: line)
            for (x, y) in zip(b, a) {
                XCTAssertEqual(x.x, y.x, accuracy: 1e-9, note, file: file, line: line)
                XCTAssertEqual(x.y, y.y, accuracy: 1e-9, note, file: file, line: line)
            }
        }
    }

    // MARK: - The box re-fits as it turns (stage 3b, phase 3)
    //
    // The owner, 2026-08-28: *"currently when the user uses the yellow node to rotate the selection
    // box, the dimensions of the box does not change to fit the drawing. That box should be the
    // bounding box of the drawing inside of it and should actively change dimensions when rotated to
    // keep on fitting the image. For example, the box would be bigger and then smaller on 45 degree
    // angle increments of a square it is around, and constant for a circle."*
    //
    // LASSO_MOVE.md §5.22. Phases 1 and 2 made the knob turn a rectangle of fixed, wrong dimensions;
    // this is what makes the hand-fit §5.19 promised actually fit. The two cases in the ask are the
    // first two tests below, in the owner's own order, and the *circle* is the one that costs
    // nothing and catches the whole wrong family: a box measured from the previous box rather than
    // from the ink grows by √2 on every eighth-turn and never comes back, which no amount of
    // squinting at a square would separate from a correct answer.

    /// **At rest the fit is the lift's own box, to the bit** — the reduction every other assertion
    /// here is measured against, and the one that has to be exact rather than close.
    ///
    /// `boxAngle == 0` with nothing stretched and nothing mirrored makes the fit's frame `R(0)`, and
    /// `CGAffineTransform(rotationAngle: 0)` is the identity exactly — so the fit walks the same
    /// points through no matrix at all and `MoveBoxInk.bounds()` is literally the call the lift made.
    /// The offset comes back an exact `.zero` because the anchor it subtracts is `pivot`, which *is*
    /// the lift box's centre. Anything less than exact here would mean the box changed size the
    /// instant the artist touched the knob and changed back when they let go.
    func testTheFittedBoxAtRestIsTheLiftsOwnBoxToTheBit() {
        for transform in [CGAffineTransform.identity,
                          CGAffineTransform(rotationAngle: 0.4).concatenating(
                            CGAffineTransform(translationX: 6, y: 9)),
                          CGAffineTransform(translationX: -3, y: 11).scaledBy(x: 1.7, y: 1.7)] {
            for kind in LiftKind.allCases {
                let (manager, layerIndex, vector) = fixture()
                vector.setTransform(transform)
                vector.addStroke(stroke(from: CGPoint(x: 8, y: 14), to: CGPoint(x: 52, y: 41), size: 6))
                vector.addStroke(stroke(from: CGPoint(x: 30, y: 6), to: CGPoint(x: 33, y: 55), size: 3))
                XCTAssertTrue(lift(kind, manager, layerIndex), "\(kind.rawValue) \(transform)")
                guard let float = manager.vectorFloat,
                      let fitted = manager.fittedMoveBoxFrame else { return XCTFail("no float") }
                let note = "\(kind.rawValue), layer \(transform)"
                XCTAssertEqual(fitted.contentSize, float.contentSize, "the lift's box, exactly — \(note)")
                XCTAssertEqual(fitted.contentOffset, .zero, "centred on the pivot — \(note)")
                XCTAssertEqual(fitted.transform, float.frame.transform, "and the pose is untouched — \(note)")
                XCTAssertEqual(fitted.allowedHandles, float.frame.allowedHandles,
                               "including which grips it offers — \(note)")
            }
        }
    }

    /// **The owner's first case: a square swells and shrinks on a 45° period.** A square of side *s*
    /// is *s* across at 0°, `s√2` at 45° — every corner on an axis of the turned frame — and *s*
    /// again at 90°.
    ///
    /// The general answer for a square turned by β is `s·(|cos β| + |sin β|)`, which is where √2 at
    /// an eighth-turn and 1 at a quarter-turn both come from, so the sweep asserts the closed form at
    /// twenty angles rather than the three the owner happened to name. **The `+ 2·reach` is not a
    /// fudge**: the ink is a stroke, its footprint is a disc of `stampRadius` about every sample, and
    /// §5.19's whole arithmetic is that the padding is applied *in the frame being measured* rather
    /// than carried round from the last one — which is exactly why a 100 × 20 bar re-lifted at 45°
    /// measures 76.57 and not 84.85. A thin brush is used so the term is small enough that the shape
    /// of the answer is visible in the numbers.
    ///
    /// The box stays centred throughout, which a square is entitled to and an asymmetric shape is
    /// not — see `testTheBoxCentreTravelsAsItRefitsAndTheGeometryAnchorDoesNot`.
    func testTheFittedBoxSwellsAndShrinksOnA45DegreePeriodAroundASquare() {
        let (manager, _, vector) = fixture()
        let side: CGFloat = 40, width: CGFloat = 2
        let lo: CGFloat = 12, hi = lo + side
        for (a, b) in [(CGPoint(x: lo, y: lo), CGPoint(x: hi, y: lo)),
                       (CGPoint(x: hi, y: lo), CGPoint(x: hi, y: hi)),
                       (CGPoint(x: hi, y: hi), CGPoint(x: lo, y: hi)),
                       (CGPoint(x: lo, y: hi), CGPoint(x: lo, y: lo))] {
            vector.addStroke(stroke(from: a, to: b, size: width))
        }
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: BrushLibrary.hardRound, size: width)

        func fitted(at boxAngle: CGFloat) -> ObjectTransformFrame {
            manager.turnVectorFloatBox(to: boxAngle)
            return manager.fittedMoveBoxFrame ?? ObjectTransformFrame(transform: .identity, contentSize: .zero)
        }

        // The three the owner named, spelled out rather than left to the sweep.
        XCTAssertEqual(fitted(at: 0).contentSize.width, side + 2 * reach, accuracy: 1e-9,
                       "s at 0° — \(fitted(at: 0).contentSize)")
        let diagonal = fitted(at: .pi / 4).contentSize
        XCTAssertEqual(diagonal.width, side * 2.0.squareRoot() + 2 * reach, accuracy: 1e-9,
                       "s√2 at 45° — \(diagonal)")
        XCTAssertEqual(diagonal.height, side * 2.0.squareRoot() + 2 * reach, accuracy: 1e-9,
                       "and square with it — \(diagonal)")
        XCTAssertEqual(fitted(at: .pi / 2).contentSize.width, side + 2 * reach, accuracy: 1e-9,
                       "and s again at 90° — \(fitted(at: .pi / 2).contentSize)")
        XCTAssertGreaterThan(diagonal.width, fitted(at: 0).contentSize.width * 1.3,
                             "it really does swell — 45° must be materially bigger than 0°")

        // And the closed form everywhere, in both directions and past a half-turn.
        for step in -10...10 {
            let angle = CGFloat(step) * .pi / 10
            let box = fitted(at: angle)
            let expected = side * (abs(cos(angle)) + abs(sin(angle))) + 2 * reach
            let note = "at \(angle) rad the box is \(box.contentSize)"
            XCTAssertEqual(box.contentSize.width, expected, accuracy: 1e-9, note)
            XCTAssertEqual(box.contentSize.height, expected, accuracy: 1e-9, note)
            XCTAssertEqual(box.contentOffset.x, 0, accuracy: 1e-9, "a square stays centred — \(note)")
            XCTAssertEqual(box.contentOffset.y, 0, accuracy: 1e-9, "a square stays centred — \(note)")
        }
    }

    /// **The owner's second case: a circle is constant at every angle** — the degenerate one, and the
    /// cheapest test in this feature by a distance.
    ///
    /// **It is what separates "measures the ink" from "measures the last box".** A fit that took the
    /// bounding box of the *previous* box would grow a disc's box by `|cos| + |sin|` every time the
    /// knob moved — √2 per eighth-turn, monotonically, forever — and a square would still look
    /// plausible while it did. There is no cheaper way to catch that family, which is why the owner
    /// named it.
    ///
    /// Two circles, because they are degenerate in different ways. A **dab** — one sample under a
    /// 24 pt brush — is a disc *exactly*, so its box is `2·reach` at every angle to the bit, and it
    /// is also the case where the point set is a single point and only the padding can be wrong. A
    /// **ring** of 256 samples is a disc the way an artist draws one: its hull is a polygon, so its
    /// turned box wobbles by `1 − cos(π/256)` — four thousandths of a point here — which is the
    /// tolerance and not a fudge.
    func testTheFittedBoxIsConstantAtEveryAngleAroundADiscAndARing() {
        for isRing in [false, true] {
            let (manager, _, vector) = fixture()
            let centre = CGPoint(x: 32, y: 32)
            let expected: CGFloat
            if isRing {
                let radius: CGFloat = 20, width: CGFloat = 2
                let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: BrushLibrary.hardRound,
                                                       size: width)
                var samples: [VectorSample] = []
                for step in 0...256 {
                    let t = CGFloat(step) / 256 * 2 * .pi
                    samples.append(VectorSample(x: centre.x + radius * cos(t),
                                                y: centre.y + radius * sin(t), pressure: 1))
                }
                vector.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound, color: black(),
                                              size: width, opacity: 1, samples: samples,
                                              composite: .paint))
                expected = 2 * radius + 2 * reach
            } else {
                let width: CGFloat = 24
                vector.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound, color: black(),
                                              size: width, opacity: 1,
                                              samples: [VectorSample(x: centre.x, y: centre.y, pressure: 1)],
                                              composite: .paint))
                expected = 2 * StrokeGeometry.stampRadius(forPressure: 1, brush: BrushLibrary.hardRound,
                                                          size: width)
            }
            XCTAssertTrue(manager.beginVectorWholeCelMove(), "ring \(isRing)")
            // A dab is a disc to the last bit; a 256-gon is one to `1 − cos(π/256)` of its radius.
            let accuracy: CGFloat = isRing ? 0.01 : 1e-9

            var widest: CGFloat = 0
            for step in 0...32 {
                let angle = CGFloat(step) / 32 * 2 * .pi
                manager.turnVectorFloatBox(to: angle)
                guard let box = manager.fittedMoveBoxFrame else { return XCTFail("no float") }
                let note = "ring \(isRing), at \(angle) rad the box is \(box.contentSize)"
                XCTAssertEqual(box.contentSize.width, expected, accuracy: accuracy, note)
                XCTAssertEqual(box.contentSize.height, expected, accuracy: accuracy, note)
                XCTAssertEqual(box.contentOffset.x, 0, accuracy: accuracy, note)
                XCTAssertEqual(box.contentOffset.y, 0, accuracy: accuracy, note)
                widest = max(widest, box.contentSize.width)
            }
            // Stated a second way, because the harm this test exists for is *accumulation*: turning
            // the knob a full circle in thirty-two steps must not have grown the box at all.
            XCTAssertLessThan(widest, expected + accuracy,
                              "ring \(isRing): a full turn in 32 steps grew the box to \(widest) "
                              + "against \(expected) — that is a box measured from the last box")
        }
    }

    /// **The box hugs the ink at every pose the float can hold — stretched, mirrored, on a
    /// transformed layer — and every edge is checked separately.**
    ///
    /// **The oracle is deliberately the other source.** `CanvasManager.fittedFrame(of:at:)` measures
    /// `float.ink`, which is the *lift's* geometry mapped by the pose; `inkInBoxUnits` measures the
    /// elements actually sitting in the cel, which have been through `VectorCanvas.mapping` for real
    /// — samples moved, a stroke's `size` scaled by `sqrt(|det|)`, a fill's `CGPath` transformed. An
    /// oracle built the first way would only prove the code agrees with itself. That the two agree is
    /// also the answer to "which geometry should the re-fit measure": they are the same ink, and the
    /// lift's is the one that is *also* right mid-drag, where the model still holds the previous
    /// nudge and the artist is looking at a bitmap under the live pose.
    ///
    /// **Four edges, not two extents.** A size that is right and a centre that is wrong passes any
    /// assertion on width and height; it fails this one twice.
    ///
    /// The stretched arm is where `padScale` earns its place: the box's local units stop being
    /// square, so the disc the brush stamps pulls back to an ellipse, and a fit that padded by the
    /// same number on both axes would be loose on one and tight on the other by `sqrt(aspect)`.
    func testTheFittedBoxHugsTheInkAtEveryPose() {
        let angles: [CGFloat] = [0, 0.3, .pi / 4, 1.1, -0.7, 2.4]
        for layer in [CGAffineTransform.identity,
                      CGAffineTransform(rotationAngle: 0.4).concatenating(
                        CGAffineTransform(translationX: 6, y: 9)),
                      CGAffineTransform(translationX: -3, y: 11).scaledBy(x: 1.6, y: 1.6)] {
            let (manager, _, vector) = fixture()
            vector.setTransform(layer)
            // A right triangle: asymmetric about both axes, so a wrong centre has nowhere to hide.
            vector.addStroke(stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10), size: 5))
            vector.addStroke(stroke(from: CGPoint(x: 50, y: 10), to: CGPoint(x: 10, y: 50), size: 5))
            vector.addStroke(stroke(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 10, y: 10), size: 5))
            XCTAssertTrue(manager.beginVectorWholeCelMove(), "layer \(layer)")

            func sweep(_ stage: String) {
                for angle in angles {
                    manager.turnVectorFloatBox(to: angle)
                    guard let float = manager.vectorFloat,
                          let box = manager.fittedMoveBoxFrame else { return XCTFail("no float") }
                    assertTheBoxHugs(vector, float, box, accuracy: 1e-7,
                                     "\(stage), layer \(layer), boxAngle \(angle)")
                }
            }

            sweep("at rest")

            // A Freeform corner drag made about a box the artist has turned — phase 2's pose, which
            // records the axis it pulled along, so the ink is now a general affine of the lift.
            manager.turnVectorFloatBox(to: 0.5)
            guard let turned = manager.fittedMoveBoxFrame else { return XCTFail("no float") }
            let drag = ObjectTransformDrag(frame: turned, handle: .bottomRight,
                                           at: turned.corners[2], freeform: true)
            let anchor = turned.centre
            let pulled = CGPoint(x: anchor.x + (turned.corners[2].x - anchor.x) * 2.4,
                                 y: anchor.y + (turned.corners[2].y - anchor.y) * 0.7)
            let pose = drag.pose(draggedTo: pulled)
            XCTAssertNotEqual(pose.aspect, 1, "fixture precondition: the drag really stretched it")
            manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect,
                                     stretchAxis: pose.stretchAxis)
            sweep("after a stretch about a turned box")

            manager.mirrorFloating(horizontal: true)
            XCTAssertNotEqual(manager.vectorFloat?.mirror, .identity,
                              "fixture precondition: the mirror took")
            sweep("after a stretch and a mirror")

            manager.nudgeVectorFloat(to: turnedBy(manager, 0.85))
            sweep("and after the green knob on top of both")
        }
    }

    /// **The box's centre travels as it re-fits, and the geometry's anchor does not.** The constraint
    /// that is easiest to get wrong and worst to get wrong.
    ///
    /// A tight box around a diagonal genuinely is not centred where the loose axis-aligned one was —
    /// a right triangle re-fitted at 45° moves its box centre by about a quarter of its own width —
    /// so the fit *has* to be able to express that, and the first assertion is that it does rather
    /// than quietly returning a centred box that does not fit. But `pivot` is what every
    /// `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` holds still and `transform.position` is
    /// where it sends it, so writing the travelled centre into either would slide the artist's
    /// drawing while they merely turned a knob — with nothing on the undo stack to give it back,
    /// which §5.21 forbids outright.
    ///
    /// **The last two assertions are the ones that would catch that**, and they are the phase-1
    /// tripwire aimed at a new field: the turn itself is silent even against a poisoned map, so it is
    /// the *zero-delta nudge* — what an artist's next drag re-derives its map from — and the bake
    /// that show a leak. `testANonZeroBoxAngleChangesNoSampleAndNoPixel` learned that the hard way
    /// against `87081de`, and an offset folded into the map fails in exactly the same place.
    func testTheBoxCentreTravelsAsItRefitsAndTheGeometryAnchorDoesNot() {
        let (manager, _, vector) = fixture()
        vector.setTransform(CGAffineTransform(rotationAngle: 0.3).concatenating(
            CGAffineTransform(translationX: 5, y: -4)))
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10), size: 4))
        vector.addStroke(stroke(from: CGPoint(x: 50, y: 10), to: CGPoint(x: 10, y: 50), size: 4))
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 10, y: 10), size: 4))
        let pixelsBefore = cgImage(vector)
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        guard let float = manager.vectorFloat else { return XCTFail("no float") }
        let pivot = float.pivot, position = float.frame.transform.position
        let samplesBefore = vector.elements.compactMap(\.stroke).map(\.samples)

        var travelled: CGFloat = 0
        for angle in [CGFloat(0.4), CGFloat.pi / 4, 1.2, -0.9, 2.7] {
            manager.turnVectorFloatBox(to: angle)
            guard let box = manager.fittedMoveBoxFrame else { return XCTFail("no float") }
            travelled = max(travelled, hypot(box.contentOffset.x, box.contentOffset.y))
            XCTAssertEqual(manager.vectorFloat?.pivot, pivot,
                           "the geometry's anchor is a `let` and must not have moved — \(angle)")
            XCTAssertEqual(manager.vectorFloat?.frame.transform.position, position,
                           "and neither is where the map sends it — \(angle)")
            XCTAssertEqual(box.centre, position,
                           "`centre` is still the anchor, not the drawn box's middle — \(angle)")
            XCTAssertNotEqual(box.projected(.zero), box.centre,
                              "…and the two really are different points here — \(angle)")
        }
        XCTAssertGreaterThan(travelled, 5,
                             "a right triangle's tight box is materially off-centre; \(travelled) pt "
                             + "of travel means the fit is quietly returning a centred box")

        assertSamplesUnmoved(vector, samplesBefore, "after five turns of the knob")
        // The moment a leak actually shows: the next gesture re-derives the map from the pose the
        // turns left behind.
        manager.nudgeVectorFloat(to: float.frame.transform)
        assertSamplesUnmoved(vector, samplesBefore, "after the zero-delta nudge that follows them")
        manager.commitVectorFloatIfNeeded()
        assertPixelsIdentical(cgImage(vector), pixelsBefore, "and the bake")
    }

    /// **The green knob turns ink and box together, so the fit does not move — and that is arithmetic
    /// rather than a special case.**
    ///
    /// The frame the fit measures in is `B⁻¹·L`, and `transform.rotation` appears in `B` and `L`
    /// identically, so it cancels: the box's size and its centre are functions of `aspect`,
    /// `boxAngle`, `stretchAxis` and the mirror, and of nothing else. That is why
    /// `CanvasManager.fittedFrame(of:at:)` has no rotation arm — and why this is asserted anyway,
    /// since "provable" and "implemented" are different claims and the whole feature is one term
    /// being in the right expression.
    ///
    /// Driven both ways an artist can turn a piece: the green knob's own drag, and the Rotate 45°
    /// button, which is the same field moved by a different door.
    func testTheGreenKnobTurnsInkAndBoxTogetherAndTheFitDoesNotMove() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 12), to: CGPoint(x: 50, y: 12), size: 5))
        vector.addStroke(stroke(from: CGPoint(x: 50, y: 12), to: CGPoint(x: 12, y: 48), size: 5))
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        manager.turnVectorFloatBox(to: 0.6)
        guard let before = manager.fittedMoveBoxFrame else { return XCTFail("no float") }

        for (label, turn) in [("a green-knob drag", { manager.nudgeVectorFloat(to: self.turnedBy(manager, 0.9)) }),
                              ("Rotate 45°", { manager.rotateFloating(eighths: 1) }),
                              ("Rotate 45° again", { manager.rotateFloating(eighths: 1) })] {
            turn()
            guard let after = manager.fittedMoveBoxFrame else { return XCTFail("no float") }
            XCTAssertEqual(after.contentSize.width, before.contentSize.width, accuracy: 1e-9,
                           "\(label) must not resize the box: \(after.contentSize) vs \(before.contentSize)")
            XCTAssertEqual(after.contentSize.height, before.contentSize.height, accuracy: 1e-9, label)
            XCTAssertEqual(after.contentOffset.x, before.contentOffset.x, accuracy: 1e-9,
                           "\(label) must not move it either")
            XCTAssertEqual(after.contentOffset.y, before.contentOffset.y, accuracy: 1e-9, label)
            XCTAssertEqual(after.boxAngle, 0.6, accuracy: 1e-12, "and the hand-fit rode along — \(label)")
            XCTAssertNotEqual(after.transform.rotation, before.transform.rotation,
                              "fixture precondition: the ink really turned — \(label)")
        }
    }

    // MARK: - Change Colour (the lasso edit that splits nothing)

    // A recolour and a move ask the same containment question and answer it with the same rules —
    // `VectorCanvas.elementIDs(insideLocalPath:)` is `splitForLassoMove`'s sibling — and then do
    // opposite things with the answer. A move cuts a straddling stroke in two and takes the inside
    // half (§5.2); a recolour cuts nothing and recolours the whole element, ink outside the loop
    // included:
    //
    // > *"changes the color of all the strokes and fills inside the selection to the current picked
    // > color. It's alright if part of the stroke is outside the selection."* — owner, 2026-08-28.
    //
    // These live in this file, next to the split they contradict, because the contradiction is the
    // design: a later session that "unifies" the two seams breaks exactly one of these two sections.

    /// The picked colour, as the artist's swatch hands it over.
    private func picked(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Undo steps recorded **since the fixture was built**. `fixture()` calls `addLayer` and
    /// `addVectorLayer`, each of which records one, so an absolute count here would be an assertion
    /// about the fixture rather than about the recolour — and "the stack is empty" would be false
    /// before the action under test had done anything at all.
    private func stepsSince(_ baseline: Int, _ manager: CanvasManager) -> Int {
        manager.history.undoStack.count - baseline
    }

    private func assertRGB(_ colour: CodableColor?, _ r: Double, _ g: Double, _ b: Double,
                           _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let colour else {
            return XCTFail("no colour to read — \(message)", file: file, line: line)
        }
        XCTAssertEqual(colour.red, r, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(colour.green, g, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(colour.blue, b, accuracy: 1e-6, message, file: file, line: line)
    }

    /// **The containment predicate answers for every kind — including the two a recolour skips.**
    ///
    /// `VectorCanvas.elementIDs(insideLocalPath:)` is a *geometric* membership test; the kind filter
    /// lives in `recolorSelection`, one level up. This test exists to keep it there, because the
    /// tempting simplification — skip erasers and images inside the predicate, since the only caller
    /// today skips them anyway — is a trap with no red test of its own.
    ///
    /// A lasso **move** rules the exact opposite for those two kinds (LASSO_MOVE.md §5.7: *"If the
    /// hole is fully inside, it moves it"*), and the owner has asked for a Move membership mode that
    /// would reuse this very predicate. If the recolour's skip were baked in here, that Move mode
    /// would silently stop carrying erasers and photos — and the failure announces itself only as ink
    /// that quietly does not travel, which nothing else in this suite would catch.
    ///
    /// Drives the engine seam directly rather than through `recolorSelection`, because the whole
    /// point is that the two disagree about eligibility while agreeing about geometry.
    func testContainmentAnswersForEveryKindIncludingTheOnesARecolourSkips() {
        let (_, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 18), to: CGPoint(x: 40, y: 18), size: 5))
        vector.addStroke(stroke(from: CGPoint(x: 22, y: 22), to: CGPoint(x: 38, y: 22),
                                size: 4, composite: .erase))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 18, y: 26, width: 20, height: 6),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 36),
                                                                     scale: 1, rotation: 0)))
        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 12
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 26, y: 40),
                                                             size: CGSize(width: 10, height: 6))))

        let path = loop(CGRect(x: 8, y: 8, width: 48, height: 48))
        let caught = vector.elementIDs(insideLocalPath: vector.localPath(fromCanvas: path)
                                                              .normalized(using: VectorCanvas.lassoFillRule))

        XCTAssertEqual(caught, Set(vector.elements.map(\.id)),
                       """
                       every kind inside the loop must come back — the eraser and the photo included. \
                       A recolour skips those two at the call site; a lasso move must carry them \
                       (LASSO_MOVE.md §5.7), so the skip may not live in the predicate.
                       """)
    }

    /// **Under Touching a straddling stroke is recoloured whole and is not cut.** The owner's
    /// 2026-08-28 sentence — *"It's alright if part of the stroke is outside the selection"* — stated
    /// as an assertion: same element count, same id, same samples, only the hue moved.
    ///
    /// **It is `.touching` here rather than the default because TODO item (23) moved that sentence off
    /// the default and onto a rule the artist picks.** Until 2026-09-02 this was the only behaviour a
    /// recolour had; it is now one of three, and Cut — the default — splits, which is
    /// `testUnderCutAStraddlingStrokeIsSplitAndOnlyTheInsidePieceIsRecoloured` below. Nothing about
    /// what Touching does changed.
    func testUnderTouchingAStraddlingStrokeIsRecolouredWholeAndIsNotCut() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let originalID = vector.elements[0].id
        let originalSamples = vector.elements[0].stroke?.samples.count

        // x ≥ 30: the middle and end samples are inside, the first one is not. `beginVectorLassoMove`
        // on this very loop makes two strokes out of it — see `testAStrokeCrossingTheLoop…`.
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.setSelectionMembership(.touching)
        manager.brushColor = picked(1, 0, 0)
        manager.recolorSelection()

        XCTAssertEqual(vector.elements.count, 1, "Touching splits nothing — the stroke stays one stroke")
        XCTAssertEqual(vector.elements[0].id, originalID, "and keeps its identity")
        XCTAssertEqual(vector.elements[0].stroke?.samples.count, originalSamples, "and every sample")
        assertRGB(vector.elements[0].stroke?.color, 1, 0, 0,
                  "the whole stroke takes the picked colour, including the part outside the loop")
    }

    /// **Under Cut a straddling stroke is split at the loop and only the inside piece is recoloured.**
    ///
    /// The owner, 2026-08-29 (TODO item (23)): *"it would have to split the strokes and other objects
    /// around the lasso border and then recolour the ones inside. Luckly, the splitting already exists
    /// in enclosed move, so you can reuse that."* This is that, and the reuse is literal —
    /// `recolorSelection` calls the same `VectorCanvas.splitForLassoMove` a lift and a Clear call, so
    /// no geometry was written for this feature.
    ///
    /// **Their word was "enclosed" and the mode that splits is Cut.** The behaviour they described is
    /// unambiguous and `LassoMembership.cutting` is the only rule that cuts at the boundary — its own
    /// doc comment says so. Reading it as `.enclosed` would have given one rule two meanings depending
    /// on which tool asked, which is the per-tool copy item (23) exists to end.
    ///
    /// **This is a change to what the default does**, and it is the one behaviour change item (23)
    /// carries: `.cutting` is the shared default, so a plain lasso-and-Recolour now leaves the outside
    /// piece behind in the old colour. Touching is one tap away and is in the same panel as the
    /// button.
    func testUnderCutAStraddlingStrokeIsSplitAndOnlyTheInsidePieceIsRecoloured() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let originalID = vector.elements[0].id

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertEqual(manager.selectionMembership, .cutting, "fixture precondition: Cut is the default")
        manager.brushColor = picked(1, 0, 0)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        XCTAssertEqual(vector.elements.count, 2, "the stroke was cut at the loop")
        let strokes = vector.elements.compactMap(\.stroke)
        XCTAssertFalse(strokes.contains { $0.id == originalID },
                       "both halves mint fresh ids, exactly as a lasso move's do")
        // Outside first, at the parent's index — `splitForLassoMove`'s own ordering.
        assertRGB(strokes[0].color, 0, 0, 0, "the piece outside the loop keeps the colour it had")
        assertRGB(strokes[1].color, 1, 0, 0, "and the piece inside takes the picked one")
        XCTAssertEqual(stepsSince(baseline, manager), 1, "one step for the split and the colour together")

        manager.undo()
        XCTAssertEqual(vector.elements.count, 1, "and one press gives back the uncut stroke")
        XCTAssertEqual(vector.elements[0].id, originalID)
        assertRGB(vector.elements[0].stroke?.color, 0, 0, 0, "in the colour it was drawn with")
    }

    /// **Under Enclosed a straddling stroke is not recoloured at all**, and the one wholly inside
    /// beside it is — the same sentence Enclosed says for a Move, said for a recolour. Nothing is cut:
    /// Enclosed catches whole elements or nothing, which is `LassoMembership.cutsAtTheBoundary`.
    func testUnderEnclosedOnlyStrokesWhollyInsideTheLoopAreRecoloured() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 36, y: 40), to: CGPoint(x: 52, y: 40), size: 6))
        let straddling = vector.elements[0].id
        let inside = vector.elements[1].id

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.setSelectionMembership(.enclosed)
        manager.brushColor = picked(1, 0, 0)
        manager.recolorSelection()

        XCTAssertEqual(vector.elements.map(\.id), [straddling, inside], "nothing was cut and nothing moved")
        assertRGB(vector.elements[0].stroke?.color, 0, 0, 0, "the straddling stroke is not wholly inside")
        assertRGB(vector.elements[1].stroke?.color, 1, 0, 0, "the enclosed one takes the colour")
    }

    /// **An Enclosed recolour that catches nothing says so, and a bare-paper one still stays silent**
    /// — LASSO_MOVE.md §5.24 reached through the recolour's door. The ruling is written about a lift
    /// and its argument names no tool: what separates the two cases is whether the artist can *see*
    /// the reason, and a loop full of ink that Enclosed excluded is the case where they cannot.
    func testAnEnclosedRecolourThatCatchesNothingSaysSoAndBarePaperStaysSilent() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        manager.setSelectionMembership(.enclosed)
        manager.brushColor = picked(1, 0, 0)

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()
        XCTAssertEqual(stepsSince(baseline, manager), 0, "no stroke lies completely inside the loop")
        assertRGB(vector.elements[0].stroke?.color, 0, 0, 0, "so nothing took the colour")
        XCTAssertEqual(manager.notice?.code, "nothingWhollyInside", "and the artist is told why")

        manager.notice = nil
        select(manager, layerIndex, loop(CGRect(x: 4, y: 44, width: 16, height: 16)))
        manager.recolorSelection()
        XCTAssertNil(manager.notice,
                     "but bare paper says nothing — §5.9, where the artist can see the reason")
    }

    /// **A Cut recolour that changes no colour leaves no cut behind.** The split is computed into a
    /// local list and only assigned when something actually took the picked colour, so a loop whose
    /// contents are already that colour costs the artist neither an undo step *nor* a stroke they now
    /// have to rejoin. This is the sharpest way the split could have leaked: `changed == 0` returning
    /// after the assignment would look identical in every other test in this file.
    func testACutRecolourThatChangesNoColourLeavesNoCutBehind() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let originalID = vector.elements[0].id

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.brushColor = picked(0, 0, 0)              // exactly what the stroke already is
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        XCTAssertEqual(vector.elements.count, 1, "the stroke is still one stroke")
        XCTAssertEqual(vector.elements[0].id, originalID, "with the id it was drawn with")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and nothing is recorded")
    }

    /// **Selection is by the centre line here too.** A 40 pt stroke whose spine is outside the loop is
    /// not recoloured, even though its ink is inside — the same knowing consequence of LASSO_MOVE.md
    /// §5.4 that `testAThickStrokeWhoseSpineIsOutside…` pins for the move, asserted again for the
    /// recolour so the two can never drift into two different answers.
    func testAThickStrokeWhoseSpineIsOutsideIsNotRecolouredEvenThoughItsInkIsInside() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 8), to: CGPoint(x: 54, y: 8), size: 40))
        select(manager, layerIndex, loop(CGRect(x: 4, y: 16, width: 56, height: 40)))
        manager.brushColor = picked(1, 0, 0)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        assertRGB(vector.elements[0].stroke?.color, 0, 0, 0, "the spine is outside, so nothing is caught")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and nothing is recorded")
    }

    /// **An eraser inside the loop is untouched, and does not count as a change.** `.erase` is
    /// composited `.destinationOut`, which reads only alpha — recolouring one changes no pixel, so
    /// doing it would spend an undo press on an edit the artist cannot see.
    ///
    /// Note this is the one place the recolour and the move part company on *which kinds* they act on.
    /// A move treats an eraser as an ordinary element (owner, 2026-08-22) because a hole has a
    /// position; a recolour skips it because a hole has no colour.
    func testAnEraserInsideTheLoopIsNotRecolouredWhileThePaintStrokeBesideItIs() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 20), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 24, y: 20), to: CGPoint(x: 40, y: 20),
                                size: 4, composite: .erase))

        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 48, height: 30)))
        manager.brushColor = picked(0, 1, 0)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        let strokes = vector.elements.compactMap(\.stroke)
        assertRGB(strokes.first { $0.composite == .paint }?.color, 0, 1, 0, "the paint stroke takes the colour")
        assertRGB(strokes.first { $0.composite == .erase }?.color, 0, 0, 0, "the eraser keeps whatever it had")
        XCTAssertEqual(strokes.filter { $0.composite == .erase }.count, 1, "and is still an eraser")
        XCTAssertEqual(stepsSince(baseline, manager), 1, "one step, for the one thing that changed")
    }

    /// **A loop that catches only an eraser and a placed photo records nothing at all.** Neither kind
    /// has a colour a recolour could change, so neither is counted — and a step that undoes to an
    /// identical document is worse than no step, because the artist presses undo expecting their own
    /// last real edit back.
    func testALoopCatchingOnlyAnEraserAndAPhotoRecordsNoHistoryStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 20),
                                size: 6, composite: .erase))
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 12, height: 12),
                                                                          size: CGSize(width: 12, height: 12)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 26),
                                                                     scale: 1, rotation: 0)))
        let before = vector.elements

        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 50, height: 34)))
        manager.brushColor = picked(1, 0, 1)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        XCTAssertEqual(stepsSince(baseline, manager), 0,
                       "nothing recolourable was caught, so no undo step is owed")
        XCTAssertEqual(vector.elements.map(\.id), before.map(\.id), "and the list is untouched")
        XCTAssertEqual(vector.elements.compactMap(\.image).count, 1, "the photo is still there")
        assertRGB(vector.elements.compactMap(\.stroke).first?.color, 0, 0, 0,
                  "the eraser's colour is left alone")
    }

    /// A lasso around bare paper is the same nothing, reached by the other door.
    func testALoopAroundBarePaperRecordsNoHistoryStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 4), to: CGPoint(x: 12, y: 6)))

        select(manager, layerIndex, loop(CGRect(x: 30, y: 30, width: 20, height: 20)))
        manager.brushColor = picked(1, 0, 0)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        XCTAssertEqual(stepsSince(baseline, manager), 0)
        assertRGB(vector.elements[0].stroke?.color, 0, 0, 0, "the far-away stroke is not touched")
    }

    /// **Under Touching a fill that merely overlaps the loop is recoloured whole, and keeps its fill
    /// rule.** The rule matters more than it looks: a clear-selection hole is stored `evenOddFill`,
    /// and a recolour that rebuilt the element with the default would fill in the very hole it exists
    /// to make.
    func testUnderTouchingAFillOverlappingTheLoopIsRecolouredWholeAndKeepsItsEvenOddRule() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 44, height: 30),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1, evenOddFill: true))
        let originalID = vector.elements[0].id
        let originalPath = vector.elements[0].fill?.pathData

        // Overlaps the fill's right-hand end only — a move, or a Cut recolour, cuts it in two here.
        select(manager, layerIndex, loop(CGRect(x: 40, y: 2, width: 24, height: 60)))
        manager.setSelectionMembership(.touching)
        manager.brushColor = picked(1, 0.5, 0)
        manager.recolorSelection()

        XCTAssertEqual(vector.elements.count, 1, "Touching splits no fill either")
        XCTAssertEqual(vector.elements[0].id, originalID)
        XCTAssertEqual(vector.elements[0].fill?.pathData, originalPath, "and moves no geometry")
        XCTAssertEqual(vector.elements[0].fill?.evenOddFill, true, "the fill rule survives the rewrite")
        assertRGB(vector.elements[0].fill?.color, 1, 0.5, 0, "the whole fill takes the picked colour")
    }

    /// **Under Cut a fill is cut at the loop and only the inside chunk takes the colour** — the
    /// owner's *"and other objects"*, which for a fill is the two Core Graphics booleans
    /// `splitForLassoMove` already runs. Both halves keep the parent's even-odd rule, which is the
    /// thing that would silently fill in a Clear-punched hole if it were dropped.
    func testUnderCutAFillIsCutAtTheLoopAndOnlyTheInsideChunkIsRecoloured() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 44, height: 30),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1, evenOddFill: true))
        let originalID = vector.elements[0].id

        select(manager, layerIndex, loop(CGRect(x: 40, y: 2, width: 24, height: 60)))
        XCTAssertEqual(manager.selectionMembership, .cutting, "fixture precondition: Cut is the default")
        manager.brushColor = picked(1, 0.5, 0)
        manager.recolorSelection()

        let fills = vector.elements.compactMap(\.fill)
        XCTAssertEqual(fills.count, 2, "the fill was cut at the loop")
        XCTAssertFalse(fills.contains { $0.id == originalID }, "and both halves mint fresh ids")
        assertRGB(fills[0].color, 0, 0, 1, "the chunk outside the loop keeps its blue")
        assertRGB(fills[1].color, 1, 0.5, 0, "and the chunk inside takes the picked colour")
        XCTAssertTrue(fills.allSatisfy { $0.evenOddFill }, "both halves carry the parent's fill rule")
    }

    /// **Text is caught by its box centre, and only by its box centre.** That is the rule
    /// `splitForLassoMove` already uses for type (LASSO_MOVE.md §5.3, and `ADD_TEXT.md` §5.4 for the
    /// eraser), kept rather than replaced: one containment answer for a text box, not one per feature.
    ///
    /// Both halves in one test on purpose — the interesting assertion is the second, where a box the
    /// loop visibly overlaps is *not* recoloured. A stroke in that position would be.
    func testTextIsRecolouredWhenItsBoxCentreIsInsideAndNotWhenItIsOutside() {
        for (name, loopRect, expectsRecolour) in [
            ("centre inside", CGRect(x: 10, y: 10, width: 44, height: 40), true),
            // The box spans x 20…36; this loop starts at x 34, so it overlaps the box's right end
            // while leaving the centre at (28, 25) outside.
            ("overlapping, centre outside", CGRect(x: 34, y: 2, width: 28, height: 60), false),
        ] as [(String, CGRect, Bool)] {
            let (manager, layerIndex, vector) = fixture()
            var recipe = TextRecipe(string: "hi")
            recipe.typography.pointSize = 17
            recipe.color = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
            let element = VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 20, y: 20),
                                                             size: CGSize(width: 16, height: 10)))
            vector.upsertText(element)

            select(manager, layerIndex, loop(loopRect))
            manager.brushColor = picked(0, 0, 1)
            let baseline = manager.history.undoStack.count
            manager.recolorSelection()

            let text = vector.elements.compactMap(\.text).first
            if expectsRecolour {
                assertRGB(text?.recipe.color, 0, 0, 1, "\(name): the box centre is inside")
                XCTAssertEqual(text?.recipe.typography.pointSize, 17, "\(name): a recolour restyles nothing else")
                XCTAssertEqual(text?.recipe.string, "hi", "\(name): nor retypes it")
                XCTAssertEqual(text?.frame.size, CGSize(width: 16, height: 10), "\(name): nor re-flows it")
            } else {
                assertRGB(text?.recipe.color, 0, 0, 0, "\(name): overlap is not enough for type")
                XCTAssertEqual(stepsSince(baseline, manager), 0, "\(name): and nothing is recorded")
            }
        }
    }

    /// **Only the hue travels.** A faint stroke stays faint, a solid one stays solid, and a fill keeps
    /// the transparency it was made with (owner, 2026-08-28).
    ///
    /// The two numbers that must *not* appear anywhere in the result are the ones a careless read of
    /// the picker would pick up: `brushColor`'s own alpha and `brushOpacity`. Every kind is carried
    /// through here at a different opacity, and the three kinds store it three different ways — a
    /// stroke in `opacity` beside an opaque `color`, a fill with it folded into `color.alpha` (which
    /// is what `fillSelection` writes), and text in `recipe.opacity`. Leaving both fields alone is
    /// what makes one write pattern right for all three.
    func testARecolourCarriesTheHueAndLeavesEveryOpacityExactlyWhereItWas() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: 5, opacity: 0.6,
                                      samples: [VectorSample(x: 20, y: 20, pressure: 1),
                                                VectorSample(x: 32, y: 20, pressure: 1)]))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 16, y: 26, width: 20, height: 8),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 0.25),
                                         opacity: 0.5))
        var recipe = TextRecipe(string: "hi")
        recipe.opacity = 0.7
        recipe.color = CodableColor(red: 0, green: 0, blue: 0, alpha: 0.4)
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 22, y: 36),
                                                             size: CGSize(width: 12, height: 8))))

        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 48, height: 44)))
        // Neither of these two may reach the artwork.
        manager.brushColor = picked(0.2, 0.4, 0.8, 0.9)
        manager.brushOpacity = 0.2
        manager.recolorSelection()

        let stroke = vector.elements.compactMap(\.stroke).first
        assertRGB(stroke?.color, 0.2, 0.4, 0.8, "the stroke takes the hue")
        XCTAssertEqual(stroke?.color.alpha, 1, "and not the picker's alpha")
        XCTAssertEqual(stroke?.opacity, 0.6, "and keeps its own opacity, not brushOpacity")

        let fill = vector.elements.compactMap(\.fill).first
        assertRGB(fill?.color, 0.2, 0.4, 0.8, "the fill takes the hue")
        XCTAssertEqual(fill?.color.alpha, 0.25,
                       "a fill stores its transparency in the alpha channel — it must survive untouched")
        XCTAssertEqual(fill?.opacity, 0.5, "and its multiplier too")

        let text = vector.elements.compactMap(\.text).first
        assertRGB(text?.recipe.color, 0.2, 0.4, 0.8, "the text takes the hue")
        XCTAssertEqual(text?.recipe.color.alpha, 0.4)
        XCTAssertEqual(text?.recipe.opacity, 0.7)
    }

    /// **One undo press puts every colour back**, across all three kinds and one step.
    func testOneUndoPressRestoresEveryColour() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 18, y: 18), to: CGPoint(x: 44, y: 18), size: 5))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 16, y: 26, width: 22, height: 8),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        var recipe = TextRecipe(string: "hi")
        recipe.color = CodableColor(red: 0, green: 0.5, blue: 0, alpha: 1)
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 22, y: 36),
                                                             size: CGSize(width: 12, height: 8))))

        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 48, height: 44)))
        manager.brushColor = picked(1, 0, 0)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()
        XCTAssertEqual(stepsSince(baseline, manager), 1, "three elements, one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .recolorSelection)

        manager.undo()

        assertRGB(vector.elements.compactMap(\.stroke).first?.color, 0, 0, 0, "the stroke's black is back")
        assertRGB(vector.elements.compactMap(\.fill).first?.color, 0, 0, 1, "the fill's blue is back")
        assertRGB(vector.elements.compactMap(\.text).first?.recipe.color, 0, 0.5, 0, "the text's green is back")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and it was one press, not three")
    }

    /// **The recolour is visible on screen, which is a different claim from "the model changed".**
    ///
    /// `VectorCanvas.elements`'s setter deliberately does not invalidate, and both the memoized
    /// `render()` and `PixelOps.rasterize`'s cache key on `version` — so an edit that writes the array
    /// and forgets `bumpVersion()` is correct in the document and invisible to the artist until
    /// something unrelated happens to move the counter. Nothing else in this file catches that: every
    /// other assertion here reads the model.
    ///
    /// The flatten is taken **before** the recolour on purpose. Without it there is no stale entry in
    /// the cache to be served, and the test would pass with the bump removed.
    ///
    /// Watched failing with `bumpVersion()` commented out: *the picked colour must reach the flatten
    /// — found 0 red pixels*, the pre-recolour bitmap served straight back out of the cache.
    func testTheRecolourReachesTheFlattenAndNotOnlyTheModel() throws {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 16, y: 32), to: CGPoint(x: 48, y: 32), size: 8))

        func redPixelCount() throws -> Int {
            let cel = manager.layers[layerIndex].cels[0]
            let flat = PixelOps.rasterize(cel: cel, canvasSize: Self.size)
            let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(flat.cgImage)))
            return stride(from: 0, to: bytes.count, by: 4).count {
                bytes[$0] > 200 && bytes[$0 + 1] < 60 && bytes[$0 + 2] < 60 && bytes[$0 + 3] > 200
            }
        }

        XCTAssertEqual(try redPixelCount(), 0, "fixture precondition: the stroke is black")

        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.brushColor = picked(1, 0, 0)
        manager.recolorSelection()

        XCTAssertGreaterThan(try redPixelCount(), 0,
                             "the picked colour must reach the flatten, not just the display list")
    }

    /// **A pixel layer refuses, and says why.** Change Colour rewrites a colour field on a stored
    /// element; a raster cel has pixels and no elements (owner, 2026-08-28: pixel layers are out of
    /// scope). `selectionMembershipUnavailableReason` beside it is the precedent — the artist gets a
    /// sentence, not a button that looks live and does nothing.
    func testChangeColourRefusesAPixelLayerWithAReasonRatherThanGoingQuietlyGrey() {
        let (manager, _, _) = fixture()
        manager.currentLayerIndex = 0                       // the raster layer the fixture starts with
        select(manager, 0, loop(CGRect(x: 8, y: 8, width: 40, height: 40)))
        manager.brushColor = picked(1, 0, 0)

        let reason = manager.recolorUnavailableReason
        XCTAssertNotNil(reason, "a raster layer must say why, not go grey")
        XCTAssertFalse(reason?.isEmpty ?? true)
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and the action itself is a no-op")
    }

    /// **An in-between refuses too**, for `TopToolbar.toggleMove`'s reason: an interpolated cel's
    /// frame is derived, so the write would land on a `VectorCanvas` the displayed image is not
    /// computed from and the artist would see nothing change.
    ///
    /// `fillSelection` and `clearSelectionPixels` are *missing* this guard — a pre-existing hole
    /// recorded in BUGS.md rather than fixed here, since changing when Fill and Clear refuse is a
    /// behaviour change nobody has put to the owner.
    func testChangeColourRefusesAnInBetweenCel() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 18, y: 20), to: CGPoint(x: 44, y: 20), size: 5))
        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 48, height: 40)))
        manager.brushColor = picked(1, 0, 0)

        XCTAssertNil(manager.recolorUnavailableReason, "fixture precondition: a keyframe is fine")
        manager.layers[layerIndex].cels[0].interpolation = InterpolationRecipe(references: [], t: 0.5)

        XCTAssertNotNil(manager.recolorUnavailableReason, "a derived cel must say why")
        let baseline = manager.history.undoStack.count
        manager.recolorSelection()
        assertRGB(vector.elements[0].stroke?.color, 0, 0, 0, "and write nothing")
        XCTAssertEqual(stepsSince(baseline, manager), 0)
    }

    /// **A recolour to the colour something already is records nothing.** The same rule as the empty
    /// catch, reached from the other side: an undo step that undoes to an identical document costs
    /// the artist a press and gives them back nothing they asked for.
    func testRecolouringToTheColourSomethingAlreadyIsRecordsNoHistoryStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 18, y: 20), to: CGPoint(x: 44, y: 20), size: 5))
        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 48, height: 40)))
        manager.brushColor = picked(0, 0, 0)              // exactly what the stroke already is

        let baseline = manager.history.undoStack.count
        manager.recolorSelection()

        XCTAssertEqual(stepsSince(baseline, manager), 0)
    }

    /// **Every fill keeps its z-position.** `addFill` appends, so a canvas can hold fills above *and*
    /// below the same stroke — a recolour that gathered the kinds into buckets and assigned them back
    /// would drag a fill the artist had just put on top back underneath the line art.
    ///
    /// The order is asserted by id rather than by kind, which is the only way to see a restack that
    /// preserves the counts.
    func testARecolourPreservesTheZOrderOfInterleavedFillsAndStrokes() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 12, y: 12, width: 30, height: 10),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        vector.addStroke(stroke(from: CGPoint(x: 14, y: 24), to: CGPoint(x: 44, y: 24), size: 5))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 12, y: 30, width: 30, height: 10),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1),
                                         opacity: 1))
        let before = vector.elements.map(\.id)
        XCTAssertNotNil(vector.elements[1].stroke, "fixture precondition: a stroke between two fills")

        select(manager, layerIndex, loop(CGRect(x: 6, y: 6, width: 50, height: 44)))
        manager.brushColor = picked(1, 0, 0)
        manager.recolorSelection()

        XCTAssertEqual(vector.elements.map(\.id), before, "the display list is rewritten in place")
        for element in vector.elements {
            assertRGB(element.fill?.color ?? element.stroke?.color, 1, 0, 0, "and all three took the colour")
        }
    }

    // MARK: - Clear on a selection (owner, 2026-08-28)
    //
    // > *"clear does not work (in the selection menu). It should clear all the stuff in the
    // > selection."* — owner, 2026-08-28, on a build they were holding.
    //
    // They were right, and the reason was that `clearSelectionPixels`' vector arm walked the display
    // list looking only at `element.fill` and `continue`d past every stroke. On a vector layer —
    // which is the default kind — Clear punched holes in filled regions and left the artist's actual
    // drawing untouched. **The first two tests here were watched failing before the fix was written**;
    // they are the reproduction, not a regression net bolted on afterwards.
    //
    // The ruling is that Clear **follows the picker, with no exception** (§5.26): under Cut only what
    // is inside vanishes and the part of a stroke hanging outside survives, under Touching a stroke
    // the loop merely grazes goes whole, and under Enclosed it does not go at all. So Clear is
    // `splitForLassoMove` under `selectionMembership` with the inside thrown away rather than lifted,
    // and these live next to the move's own tests because the two must give the same answer to "what
    // did the loop catch" — a session that changes one has to look at the other.
    //
    // **The tests below that set no membership are asserting Cut**, which is the default and is what
    // §5.25 rules Clear means there; the three named `testUnder…Clear…` are the other two rules.

    /// **A stroke wholly inside the loop is cleared.** The owner's sentence as an assertion, and the
    /// first of the two that were red on the old code: the walk it replaced skipped `.stroke`
    /// entirely, so an artist who draws with strokes pressed a button that did nothing at all.
    func testAStrokeWhollyInsideTheLoopIsCleared() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 20), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 48, height: 30)))
        let baseline = manager.history.undoStack.count
        manager.clearSelectionPixels()

        XCTAssertTrue(vector.elements.isEmpty, "the stroke the loop caught is gone")
        XCTAssertEqual(stepsSince(baseline, manager), 1, "one undo step for the one gesture")
        XCTAssertEqual(manager.history.undoStack.last?.label, .clearSelection)
    }

    /// **Clearing blank paper must not paint a distant fill's colour into the loop**, and on the old
    /// code it did. `clipPath(_:excluding:)` concatenated the loop onto *every* fill in the list with
    /// no bounds test and forced `evenOddFill`, so for a fill the loop did not overlap the two
    /// regions were disjoint, each wound once, and even-odd filled **both** — the artist cleared an
    /// empty corner and watched it turn blue.
    ///
    /// The second of the two reproduction tests, and the one nobody had reported: it is the reason
    /// the helper is deleted rather than merely bypassed.
    func testClearingBlankPaperDoesNotPaintADistantFillsColourIntoTheLoop() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 2, y: 2, width: 10, height: 10),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        let before = vector.elements
        select(manager, layerIndex, loop(CGRect(x: 30, y: 30, width: 20, height: 20)))
        let baseline = manager.history.undoStack.count
        manager.clearSelectionPixels()

        XCTAssertFalse(isOpaque(vector, at: CGPoint(x: 40, y: 40)),
                       "the cleared corner stays bare paper")
        XCTAssertTrue(isOpaque(vector, at: CGPoint(x: 6, y: 6)), "and the fill across the canvas is untouched")
        XCTAssertEqual(vector.elements.map(\.id), before.map(\.id), "no element was rewritten")
        XCTAssertEqual(stepsSince(baseline, manager), 0,
                       "a clear that catches nothing is a silent no-op with no undo step")
    }

    /// **A straddling stroke is cut, and the outside half keeps its geometry.** This is the half that
    /// makes Clear an eraser rather than a delete key: the artist loops half a line and gets the
    /// other half back intact, ending exactly at the boundary they drew.
    ///
    /// The `seedID` assertion is the reason this reuses `splitForLassoMove` rather than filtering the
    /// list by hand. A cut piece renders on its parent's `DabLattice`, so the half that stayed keeps
    /// its dab phase and a scattering brush does not visibly re-roll along the part the artist did
    /// *not* touch — the precise defect `DabLattice` exists to prevent, and it comes free here.
    func testAStrokeStraddlingTheLoopIsCutAndTheOutsideHalfKeepsItsGeometry() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let originalID = vector.elements[0].id

        // x ≥ 30: the middle and end samples are inside, the first one is not.
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.clearSelectionPixels()

        XCTAssertEqual(vector.elements.count, 1, "one half survives, and it is one stroke")
        guard let survivor = vector.elements.first?.stroke else {
            return XCTFail("the survivor is a stroke")
        }
        XCTAssertEqual(survivor.samples.first?.x ?? .nan, 6, accuracy: 1e-6,
                       "the outside end is exactly where the artist drew it")
        XCTAssertEqual(survivor.samples.last?.x ?? .nan, 30, accuracy: 0.5,
                       "and the cut lands on the loop, not at the previous stored sample")
        XCTAssertNotEqual(survivor.id, originalID, "a split makes two independent strokes (§5.2)")
        XCTAssertEqual(survivor.lattice?.seedID, originalID,
                       "but it draws on its parent's lattice, so its dabs do not re-phase")
        XCTAssertTrue(isOpaque(vector, at: CGPoint(x: 12, y: 20)), "ink outside the loop stayed")
        XCTAssertFalse(isOpaque(vector, at: CGPoint(x: 44, y: 20)), "ink inside the loop went")
    }

    /// **A fill still clips, and a hole punched by an older build of Clear stays a hole.** The
    /// regression this change had the most room to break: the fills the app has already saved carry
    /// `evenOddFill: true` because the deleted helper made them that way, and cutting one as a
    /// winding path would fill in the very hole it exists to make.
    ///
    /// `splitForLassoMove` cuts each fill with its own stored rule, so this passes for the documents
    /// on the owner's iPad as well as for the ones a future Clear will make.
    func testAFillWithAHoleIsCutWithItsOwnEvenOddRuleAndKeepsTheHole() {
        let (manager, layerIndex, vector) = fixture()
        let ring = CGMutablePath()
        ring.addRect(CGRect(x: 8, y: 8, width: 48, height: 48))
        ring.addRect(CGRect(x: 24, y: 24, width: 16, height: 16))
        vector.addFill(VectorFillElement(path: ring,
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1, evenOddFill: true))
        XCTAssertFalse(isOpaque(vector, at: CGPoint(x: 32, y: 32)), "fixture precondition: a hole")

        select(manager, layerIndex, loop(CGRect(x: 44, y: 0, width: 20, height: 64)))
        manager.clearSelectionPixels()

        // `guard`, not a subscript: `XCTAssertEqual` does not stop the test, so indexing here on a
        // list this clear had emptied would trap and take the **other 122 tests in the class** down
        // with it — a real regression would be reported as one crash instead of one red assertion.
        // Found by mutation-testing this very file, where exactly that happened.
        XCTAssertEqual(vector.elements.count, 1, "the outside remnant is one fill, not one per component")
        guard let remnant = vector.elements.first?.fill else { return XCTFail("the survivor is a fill") }
        XCTAssertTrue(remnant.evenOddFill, "cut with, and keeping, its own rule")
        XCTAssertTrue(isOpaque(vector, at: CGPoint(x: 12, y: 32)), "the part outside the loop stayed")
        XCTAssertFalse(isOpaque(vector, at: CGPoint(x: 50, y: 32)), "the part inside it went")
        XCTAssertFalse(isOpaque(vector, at: CGPoint(x: 32, y: 32)), "and the hole is still a hole")
    }

    /// **A fill wholly inside the loop is deleted, not hollowed to an empty shell.** The old walk
    /// left every fill in the list whatever happened to it, so a cel cleared twenty times carried
    /// twenty invisible elements into the saved document. Deleting is what makes the display list
    /// shrink when the drawing does.
    func testAFillWhollyInsideTheLoopIsDeletedRatherThanHollowed() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 20, y: 20, width: 16, height: 16),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        select(manager, layerIndex, loop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.clearSelectionPixels()

        XCTAssertTrue(vector.elements.isEmpty, "nothing invisible is left behind in the document")
    }

    /// **An eraser mark is an ordinary element here**, exactly as it is for a move (owner,
    /// 2026-08-22): a hole inside the loop is cleared with the ink around it. This is the one place
    /// Clear and Change Colour part company — a recolour skips `.erase` because a hole has no colour,
    /// while a clear removes it because a hole has a position.
    func testAnEraserStrokeInsideTheLoopIsClearedLikeAnyOtherElement() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 8, y: 54), to: CGPoint(x: 52, y: 54), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 40, y: 20),
                                size: 5, composite: .erase))

        select(manager, layerIndex, loop(CGRect(x: 10, y: 8, width: 44, height: 28)))
        manager.clearSelectionPixels()

        XCTAssertEqual(vector.elements.count, 1, "the punch inside the loop was cleared")
        XCTAssertEqual(vector.elements.first?.stroke?.composite, .paint,
                       "and the paint stroke outside it stayed")
    }

    /// **Text cannot be cut, so a box whose *centre* the loop contains goes whole and one whose edge
    /// it merely clips does not go at all.** Both directions asserted, because either alone would
    /// pass on a rule that answers every box the same way.
    ///
    /// Not a rule invented for Clear: it is Cut's rule for the kinds with no spine (LASSO_MOVE.md
    /// §5.3), the cut rule rounded to the nearest whole object, and the same answer a lasso move and
    /// a recolour give. Choosing anything else would mean one loop caught a text box for Move and not
    /// for Clear.
    func testATextBoxIsClearedWholeByItsCentreAndOneMerelyClippedIsUntouched() {
        let (manager, layerIndex, vector) = fixture()
        var caughtRecipe = TextRecipe(string: "caught")
        caughtRecipe.typography.pointSize = 10
        vector.upsertText(VectorTextElement(id: UUID(), recipe: caughtRecipe,
                                            frame: TextFrame(origin: CGPoint(x: 20, y: 20),
                                                             size: CGSize(width: 12, height: 8))))
        var clippedRecipe = TextRecipe(string: "clipped")
        clippedRecipe.typography.pointSize = 10
        vector.upsertText(VectorTextElement(id: UUID(), recipe: clippedRecipe,
                                            frame: TextFrame(origin: CGPoint(x: 36, y: 16),
                                                             size: CGSize(width: 20, height: 10))))

        // Covers x ≤ 40: the first box's centre (26, 24) is inside; the second box overlaps the loop
        // from x = 36 to x = 40 but its centre (46, 21) is outside.
        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 30, height: 30)))
        manager.clearSelectionPixels()

        XCTAssertEqual(vector.elements.compactMap { $0.text?.recipe.string }, ["clipped"],
                       "the box the loop is centred on goes whole; the one it clips is left alone")
    }

    /// **A placed image follows the same centre rule, in both directions** — the second kind that
    /// cannot be parted, answered the same way for the same reason.
    func testAPlacedImageIsClearedWholeByItsCentreAndOneMerelyClippedIsUntouched() {
        let (manager, layerIndex, vector) = fixture()
        let caught = VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                       rect: CGRect(x: 0, y: 0, width: 12, height: 12),
                                                                       size: CGSize(width: 12, height: 12)),
                                        transform: LayerTransform(position: CGPoint(x: 24, y: 24),
                                                                  scale: 1, rotation: 0))
        let clipped = VectorImageElement(image: CanvasFixture.solidImage(.red,
                                                                        rect: CGRect(x: 0, y: 0, width: 20, height: 12),
                                                                        size: CGSize(width: 20, height: 12)),
                                         transform: LayerTransform(position: CGPoint(x: 46, y: 20),
                                                                   scale: 1, rotation: 0))
        vector.addImage(caught)
        vector.addImage(clipped)

        // Covers x ≤ 40: `caught` is centred at (24, 24); `clipped` spans x = 36…56 and so pokes into
        // the loop, but its centre (46, 20) is outside it.
        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 30, height: 30)))
        manager.clearSelectionPixels()

        XCTAssertEqual(vector.elements.map(\.id), [clipped.id],
                       "the photo the loop is centred on goes whole; the one it clips is left alone")
    }

    /// **One undo press puts everything back** — the cut halves, the deleted whole objects and the
    /// z-order, in one step rather than one per element the clear happened to touch.
    func testOneUndoPressRestoresEverythingAClearRemoved() {
        let (manager, layerIndex, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 40, height: 12),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 30), to: CGPoint(x: 58, y: 30), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 44), to: CGPoint(x: 36, y: 44), size: 5))
        let before = vector.elements.map(\.id)
        let inkBefore = opaquePixelCount(vector)

        select(manager, layerIndex, loop(CGRect(x: 14, y: 4, width: 40, height: 56)))
        manager.clearSelectionPixels()
        XCTAssertNotEqual(vector.elements.map(\.id), before, "fixture precondition: the clear did something")

        manager.undo()

        XCTAssertEqual(vector.elements.map(\.id), before,
                       "every element is back, with its identity and its z-position")
        XCTAssertEqual(opaquePixelCount(vector), inkBefore, "and so is every pixel of ink")
    }

    /// **A clear that catches nothing records no history step**, even on a cel full of ink. The
    /// artist presses Undo expecting their own last real edit back, not a step that undoes to an
    /// identical document — the same rule `recolorSelection` and `bakePreciseStrokes` state.
    ///
    /// `splitForLassoMove` answers this by returning nil, which for a lift means "nothing to carry"
    /// and here means "nothing to delete". The distinction matters because the nil is also the
    /// guarantee that nothing was *cut*: it cuts only when a piece lands inside.
    func testAClearThatCatchesNothingRecordsNoHistoryStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 8), size: 5))
        let before = vector.elements.map(\.id)

        select(manager, layerIndex, loop(CGRect(x: 4, y: 40, width: 40, height: 20)))
        let baseline = manager.history.undoStack.count
        manager.clearSelectionPixels()

        XCTAssertEqual(vector.elements.map(\.id), before, "the display list is untouched")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "and nothing is recorded")
    }

    /// **Under Touching a Clear deletes a straddling stroke whole**, ink outside the loop included.
    ///
    /// This is the consequence the owner was shown before ruling and chose anyway (LASSO_MOVE.md
    /// §5.26): §5.25 weighed "delete whole caught strokes" and declined it *as the fixed rule*, and
    /// putting Clear on the picker makes it one of the three the artist can ask for. One rule for
    /// every tool beat a Clear that answered to a rule of its own.
    func testUnderTouchingAClearDeletesAStraddlingStrokeWhole() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.setSelectionMembership(.touching)
        let baseline = manager.history.undoStack.count
        manager.clearSelectionPixels()

        XCTAssertTrue(vector.elements.isEmpty, "the whole stroke went, not just the inside half")
        XCTAssertEqual(stepsSince(baseline, manager), 1, "in one step")

        manager.undo()
        XCTAssertEqual(vector.elements.count, 1, "and one press gives it back")
    }

    /// **Under Enclosed a Clear leaves a straddling stroke and takes the one wholly inside.** The
    /// same sentence Enclosed says for a lift and for a recolour, said for Clear — which is what
    /// "no exception" means (§5.26).
    func testUnderEnclosedAClearTakesOnlyWhatLiesWhollyInsideTheLoop() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 36, y: 40), to: CGPoint(x: 52, y: 40), size: 6))
        let straddling = vector.elements[0].id

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.setSelectionMembership(.enclosed)
        manager.clearSelectionPixels()

        XCTAssertEqual(vector.elements.map(\.id), [straddling],
                       "the enclosed stroke went whole and the straddling one was not even cut")
    }

    /// **An Enclosed Clear that catches nothing says so, and bare paper still stays silent** —
    /// §5.24 reached through the third door. The ruling names no tool: a loop full of ink that the
    /// rule the artist just picked excluded is the case where they cannot see the reason.
    func testAnEnclosedClearThatCatchesNothingSaysSoAndBarePaperStaysSilent() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        manager.setSelectionMembership(.enclosed)

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        let baseline = manager.history.undoStack.count
        manager.clearSelectionPixels()
        XCTAssertEqual(vector.elements.count, 1, "no stroke lies completely inside the loop")
        XCTAssertEqual(stepsSince(baseline, manager), 0, "so nothing was deleted and nothing recorded")
        XCTAssertEqual(manager.notice?.code, "nothingWhollyInside", "and the artist is told why")

        manager.notice = nil
        select(manager, layerIndex, loop(CGRect(x: 4, y: 44, width: 16, height: 16)))
        manager.clearSelectionPixels()
        XCTAssertNil(manager.notice,
                     "but bare paper says nothing — §5.9, where the artist can see the reason")
    }

    /// **One rule, read by all three consumers.** The core claim of §5.26 stated where it can fail:
    /// one manager, one `setSelectionMembership` call, and the same loop answered identically by a
    /// recolour, a lift and a Clear. Three fixtures each setting their own value would still pass if
    /// the three tools read three properties.
    func testTheSameRuleGovernsARecolourALiftAndAClear() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let originalID = vector.elements[0].id
        let rect = CGRect(x: 30, y: 2, width: 30, height: 60)
        select(manager, layerIndex, loop(rect))
        manager.setSelectionMembership(.touching)

        manager.brushColor = picked(1, 0, 0)
        manager.recolorSelection()
        XCTAssertEqual(vector.elements.map(\.id), [originalID], "Touching recoloured it whole")

        select(manager, layerIndex, loop(rect))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(manager.vectorFloat?.insideIDs, [originalID], "and lifts it whole")
        manager.cancelVectorFloat()

        select(manager, layerIndex, loop(rect))
        manager.clearSelectionPixels()
        XCTAssertTrue(vector.elements.isEmpty,
                      "and deletes it whole — one property, three consumers, no exception")
    }

    /// **The clear is visible through `PixelOps.rasterize`, which is what proves `bumpVersion()` ran.**
    ///
    /// `VectorCanvas.elements`' setter deliberately does not invalidate, and both `RasterizeKey` and
    /// `LayerContentVersion` key on `vectorVersion` — so a clear that forgot the bump would empty the
    /// display list and leave the artist looking at their drawing. Asking through the cache, after
    /// warming it with the pre-clear flatten, is the only assertion that can tell the two apart:
    /// `vector.render()` would pass either way.
    func testTheClearIsVisibleThroughTheRasterizeCacheAndNotOnlyInTheModel() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 44, y: 20), size: 8))
        XCTAssertTrue(isOpaqueThroughRasterize(manager, layerIndex, at: CGPoint(x: 32, y: 20)),
                      "fixture precondition: the flatten is warm and carries the stroke")

        select(manager, layerIndex, loop(CGRect(x: 10, y: 10, width: 48, height: 30)))
        manager.clearSelectionPixels()

        XCTAssertFalse(isOpaqueThroughRasterize(manager, layerIndex, at: CGPoint(x: 32, y: 20)),
                       "the clear reaches the flatten every on-screen tier is built from")
    }

    /// The active cel flattened the way the compositor flattens it — **through the memoized path**,
    /// so a stale entry is a failure rather than something the test quietly renders past.
    private func isOpaqueThroughRasterize(_ manager: CanvasManager, _ layerIndex: Int,
                                          at point: CGPoint) -> Bool {
        let image = PixelOps.rasterize(cel: manager.layers[layerIndex].cels[0],
                                       canvasSize: LassoMoveLogicTests.size)
        guard let cg = image.cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return false }
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return false }
        return bytes[(y * cg.width + x) * 4 + 3] > 128
    }

    // MARK: - Three membership rules (TODO item (20))
    //
    // `Enclosed · Cut · Touching`, ordered by how much travels with the default in the middle. These
    // drive the **engine** seam — `VectorCanvas.splitForLassoMove(insideLocalPath:membership:)` —
    // because that is where the rule lives; the picker that chooses it, and what a re-lift costs, are
    // asserted in the section below this one.

    /// The split as one of the three rules produces it, from a canvas-space rectangle — both
    /// preconditions applied exactly as `beginVectorLassoMove` applies them.
    private func split(_ vector: VectorCanvas, _ rect: CGRect, _ membership: LassoMembership)
        -> (elements: [VectorElement], insideIDs: Set<UUID>, mayDiverge: Bool)? {
        vector.splitForLassoMove(insideLocalPath: vector.localPath(fromCanvas: loop(rect))
                                                        .normalized(using: VectorCanvas.lassoFillRule),
                                 membership: membership)
    }

    /// **The one test that says what the three modes are**, on the case that separates them: one
    /// stroke straddling the loop, one wholly inside it.
    ///
    ///  * **Cut** splits the straddler and carries the inside half — four samples' worth of geometry
    ///    where there were three, and a fresh id.
    ///  * **Touching** carries the straddler **whole**, ink outside the loop included, and cuts
    ///    nothing: same count, same ids.
    ///  * **Enclosed** leaves the straddler where it is and carries only the stroke that is wholly
    ///    inside — again cutting nothing.
    ///
    /// The element *count* is the load-bearing assertion in the two new modes. It is what says they
    /// mint no geometry: no bisection, no fresh ids, no lattice re-keying, and no interpolation-tier
    /// demotion, since the stroke count a keyframe pair is matched on does not change.
    func testTheThreeModesCutTouchOrEncloseAStraddlingStroke() {
        let (_, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 36, y: 40), to: CGPoint(x: 50, y: 40), size: 6))
        let straddler = vector.elements[0].id
        let wholly = vector.elements[1].id
        let rect = CGRect(x: 30, y: 2, width: 30, height: 60)

        let cut = split(vector, rect, .cutting)
        XCTAssertEqual(cut?.elements.count, 3, "Cut splits the straddler in two and leaves the other")
        XCTAssertEqual(cut?.insideIDs.count, 2)
        XCTAssertFalse(cut?.insideIDs.contains(straddler) ?? true,
                       "the parent is gone under Cut — both halves are fresh ids")

        let touching = split(vector, rect, .touching)
        XCTAssertEqual(touching?.elements.count, 2, "Touching cuts nothing")
        XCTAssertEqual(touching?.insideIDs, [straddler, wholly],
                       "and carries the straddler whole, ink outside the loop included")
        XCTAssertEqual(touching?.elements.map(\.id), vector.elements.map(\.id),
                       "the display list comes back verbatim — no fresh ids, nothing re-ordered")

        let enclosed = split(vector, rect, .enclosed)
        XCTAssertEqual(enclosed?.elements.count, 2, "Enclosed cuts nothing either")
        XCTAssertEqual(enclosed?.insideIDs, [wholly],
                       "and leaves the straddler behind — it is not completely inside")
    }

    /// **Under Enclosed a stroke is still selected by its centre line** (LASSO_MOVE.md §5.4), so a
    /// thick stroke whose spine is enclosed travels whole even where its ink pokes out of the loop.
    ///
    /// Asserted as **correct**, not as a defect. The alternative — an outline-based Enclosed — fails
    /// in the worse direction, leaving such a stroke behind *silently* with nothing on screen to
    /// explain it; and ink membership has no primitive in this codebase (§1). The ink genuinely does
    /// hang outside, which is what the first assertion measures rather than assumes.
    func testAThickStrokeWhoseSpineIsEnclosedTravelsWholeEvenWhereItsInkPokesOut() {
        let (_, _, vector) = fixture()
        // Spine along y = 30, 60 pt wide: the ink reaches y = 0 and y = 60.
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 54, y: 30), size: 60))
        let id = vector.elements[0].id
        // The loop holds the whole spine (x 10…54, y 30) and none of the ink's top or bottom.
        let rect = CGRect(x: 4, y: 10, width: 56, height: 40)
        let ink = inkBounds(vector)
        XCTAssertLessThan(ink?.minY ?? 99, rect.minY, "the ink really does hang out of the loop above")
        XCTAssertGreaterThan(ink?.maxY ?? 0, rect.maxY, "and below")

        let enclosed = split(vector, rect, .enclosed)
        XCTAssertEqual(enclosed?.insideIDs, [id],
                       "the spine is inside, so the stroke travels whole — §5.4, in every mode")
        XCTAssertEqual(enclosed?.elements.count, 1, "and is not cut")
    }

    /// **Text follows the mode in Touching and Enclosed, and keeps the centre rule in Cut** (owner,
    /// 2026-08-28) — so each of the two new modes has one sentence true of every kind, while Cut
    /// keeps what it has always been: the cut rule rounded for a kind that cannot be cut.
    ///
    /// The interesting pose is a box whose **centre is in and whose corner is out**: Cut and Touching
    /// take it, Enclosed does not. Then a loop that swallows the box whole, where all three agree.
    func testATextBoxCentreInButNotEnclosedFollowsTheModeAndKeepsTheCentreRuleInCut() {
        let (_, _, vector) = fixture()
        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 12
        let element = VectorTextElement(id: UUID(), recipe: recipe,
                                        frame: TextFrame(origin: CGPoint(x: 20, y: 20),
                                                         size: CGSize(width: 16, height: 10)))
        vector.upsertText(element)

        // The box spans x 20…36; the loop starts at x = 24, so the left strip is outside it. Its
        // centre (28, 25) is inside.
        let clipped = CGRect(x: 24, y: 18, width: 20, height: 20)
        XCTAssertEqual(split(vector, clipped, .cutting)?.insideIDs, [element.id],
                       "Cut keeps the centre rule — the box's middle is inside the loop")
        XCTAssertEqual(split(vector, clipped, .touching)?.insideIDs, [element.id],
                       "Touching takes it too — the loop reaches the box")
        XCTAssertNil(split(vector, clipped, .enclosed),
                     "Enclosed does not: a corner of the box is outside the loop")

        let swallowed = CGRect(x: 14, y: 14, width: 30, height: 24)
        for membership in LassoMembership.allCases {
            XCTAssertEqual(split(vector, swallowed, membership)?.insideIDs, [element.id],
                           "a box wholly inside the loop travels under \(membership.displayName)")
        }
    }

    /// **A placed image is answered by its own quad in Touching and Enclosed, and by its centre in
    /// Cut** — the same ruling as text, and the case that shows the two really are different rules is
    /// a loop that clips a corner of the photo without covering its middle.
    ///
    /// A corners-only containment test would be wrong here and is not what this asks: `subtracting`
    /// is a region operation, so a loop that leaves any part of the rectangle uncovered fails
    /// Enclosed however its four corners happen to fall.
    func testAPlacedImageFollowsItsOwnQuadInTouchingAndEnclosedAndItsCentreInCut() {
        let (_, _, vector) = fixture()
        vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                          rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                          size: CGSize(width: 6, height: 6)),
                                           transform: LayerTransform(position: CGPoint(x: 30, y: 36),
                                                                     scale: 1, rotation: 0)))
        let id = vector.elements[0].id
        // The photo occupies x 27…33, y 33…39, centred at (30, 36).

        // A loop that clips its right-hand strip and misses the centre entirely.
        let clipping = CGRect(x: 32, y: 30, width: 16, height: 16)
        XCTAssertNil(split(vector, clipping, .cutting),
                     "Cut asks for the centre, and the centre is outside this loop")
        XCTAssertEqual(split(vector, clipping, .touching)?.insideIDs, [id],
                       "Touching asks the quad, and the loop reaches it")
        XCTAssertNil(split(vector, clipping, .enclosed), "and Enclosed is a long way from satisfied")

        // A loop holding the centre but not the left edge.
        let partial = CGRect(x: 28, y: 30, width: 20, height: 20)
        XCTAssertEqual(split(vector, partial, .cutting)?.insideIDs, [id])
        XCTAssertEqual(split(vector, partial, .touching)?.insideIDs, [id])
        XCTAssertNil(split(vector, partial, .enclosed), "x 27…28 of the photo is still outside")

        let swallowed = CGRect(x: 20, y: 30, width: 20, height: 20)
        XCTAssertEqual(split(vector, swallowed, .enclosed)?.insideIDs, [id],
                       "and a loop that covers the whole photo takes it")
    }

    /// **An eraser mark inside the loop travels in all three modes** — LASSO_MOVE.md §5.7, verbatim:
    /// *"If the hole is fully inside, it moves it."*
    ///
    /// The failure this guards against is silent: item (19)'s recolour skips `.erase` strokes and
    /// placed images at its own call site, and folding that skip down into the shared predicate would
    /// make the two new Move modes quietly stop carrying holes. Nothing renders wrong — the ink just
    /// does not travel.
    func testAnEraserMarkInsideTheLoopTravelsInEveryMode() {
        let (_, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 32), to: CGPoint(x: 60, y: 32), size: 24))
        vector.addStroke(stroke(from: CGPoint(x: 30, y: 32), to: CGPoint(x: 40, y: 32),
                                size: 10, composite: .erase))
        let punch = vector.elements[1].id
        let rect = CGRect(x: 26, y: 24, width: 24, height: 18)

        for membership in LassoMembership.allCases {
            let caught = split(vector, rect, membership)?.insideIDs ?? []
            XCTAssertTrue(caught.contains(punch),
                          "a hole wholly inside the loop travels under \(membership.displayName) — §5.7")
        }
    }

    /// A fill straddling the loop: **Cut takes the chunk, the other two take the fill whole or not at
    /// all**, and neither of them re-archives a path.
    func testAFillFollowsTheModeAndIsCutOnlyUnderCut() {
        let (_, _, vector) = fixture()
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 44, height: 30),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        let id = vector.elements[0].id
        let straddling = CGRect(x: 24, y: 2, width: 40, height: 60)

        XCTAssertEqual(split(vector, straddling, .cutting)?.elements.count, 2, "Cut splits the fill")
        let touching = split(vector, straddling, .touching)
        XCTAssertEqual(touching?.elements.count, 1, "Touching cuts nothing")
        XCTAssertEqual(touching?.insideIDs, [id], "and carries the fill whole, its own id intact")
        XCTAssertNil(split(vector, straddling, .enclosed), "and Enclosed leaves it where it is")

        let swallowed = CGRect(x: 2, y: 2, width: 60, height: 44)
        XCTAssertEqual(split(vector, swallowed, .enclosed)?.insideIDs, [id],
                       "a fill wholly inside the loop travels under Enclosed, uncut")
        XCTAssertEqual(split(vector, swallowed, .enclosed)?.elements.count, 1)
    }

    /// **`mayDiverge` is still asked in the two new modes — and Enclosed fires it *less* often, not
    /// more.**
    ///
    /// The scoping pass for this item predicted the opposite (*"fewer moved ids means more punches
    /// above the lowest"*), and the arithmetic says otherwise: an element that is *wholly* inside the
    /// loop is moved under Cut as well as under Enclosed, so Enclosed's moved set is a **subset** of
    /// Cut's, its lowest moved index is therefore at least as high, and the scan for unmoved punches
    /// above it covers a subset of the same rows. Touching's moved set is a superset the other way.
    /// So the latch drops at least as often under Touching as under Cut, and at least as often under
    /// Cut as under Enclosed.
    ///
    /// This is the arrangement that separates all three: a straddling paint stroke at the bottom, an
    /// eraser punch above it that the loop never reaches, and a stroke wholly inside at the top.
    /// Under Cut and Touching the straddler travels (whole or in half) from *below* the punch, which
    /// strands the punch above moving ink; under Enclosed only the top stroke moves and the punch is
    /// beneath it, where it changes nothing.
    ///
    /// Keeping the latch in every mode is what makes the artist's preview the truth between gestures.
    func testMayDivergeIsAskedInEveryModeAndEnclosedFiresItLeastOften() {
        let (_, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        vector.addStroke(stroke(from: CGPoint(x: 8, y: 50), to: CGPoint(x: 16, y: 50),
                                size: 8, composite: .erase))
        vector.addStroke(stroke(from: CGPoint(x: 36, y: 40), to: CGPoint(x: 50, y: 40), size: 6))
        let rect = CGRect(x: 30, y: 2, width: 30, height: 60)

        XCTAssertEqual(split(vector, rect, .touching)?.mayDiverge, true,
                       "the straddler travels from below the punch, so the punch is stranded above it")
        XCTAssertEqual(split(vector, rect, .cutting)?.mayDiverge, true,
                       "and its inside half does the same")
        XCTAssertEqual(split(vector, rect, .enclosed)?.mayDiverge, false,
                       "under Enclosed only the top stroke moves, and nothing punches above it")
    }

    /// **Touching is item (19)'s predicate, reused rather than re-derived** — for the two kinds where
    /// the recolour and Move agree about geometry, the same loop must give the same answer through
    /// both doors.
    ///
    /// The two deliberately **disagree** about text and images, which is the ruling this test pins
    /// the other half of: `elementIDs` defaulted (`.cutting`, the cut rule rounded for the kinds that
    /// cannot be cut) answers those two by their centre, and Touching answers them by their quad.
    ///
    /// The parenthesis used to read *"the recolour's rule"* and no longer does: since TODO item (23)
    /// a recolour reads `CanvasManager.selectionMembership` like everything else, and under `.cutting`
    /// it goes through `splitForLassoMove` rather than through this door at all.
    func testTouchingIsTheSamePredicateTheRecolourAsksThroughItsOwnDoor() {
        let (_, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 30, width: 44, height: 10),
                                                      transform: nil),
                                         color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                         opacity: 1))
        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 12
        vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                            frame: TextFrame(origin: CGPoint(x: 20, y: 44),
                                                             size: CGSize(width: 16, height: 10))))
        let text = vector.elements[2].id
        let rect = CGRect(x: 30, y: 2, width: 30, height: 60)
        let local = vector.localPath(fromCanvas: loop(rect)).normalized(using: VectorCanvas.lassoFillRule)

        XCTAssertEqual(split(vector, rect, .touching)?.insideIDs,
                       vector.elementIDs(insideLocalPath: local, membership: .touching),
                       "one answer to 'what did the loop catch', whichever door asks it")

        // The text box spans x 20…36 and its centre is at x = 28 — outside the loop, which starts at
        // x = 30, while its right-hand strip is inside it.
        XCTAssertFalse(vector.elementIDs(insideLocalPath: local).contains(text),
                       "the defaulted rule answers text by its centre, and misses it")
        XCTAssertTrue(vector.elementIDs(insideLocalPath: local, membership: .touching).contains(text),
                      "Touching answers it by its quad, and takes it")
    }

    // MARK: - The membership picker, and what changing the rule costs

    /// **The rule the artist picks applies at the next lift, and the shipped rule is the default.**
    func testTheDefaultRuleIsCutAndAChosenRuleAppliesAtTheNextLift() {
        let (manager, layerIndex, vector) = fixture()
        XCTAssertEqual(manager.selectionMembership, .cutting,
                       "nothing changes until the artist touches the picker")
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let id = vector.elements[0].id

        // No float, so this is a plain assignment: there is nothing to re-lift.
        manager.setSelectionMembership(.touching)
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        XCTAssertEqual(vector.elements.count, 1, "Touching cut nothing")
        XCTAssertEqual(manager.vectorFloat?.insideIDs, [id], "and lifted the stroke whole")
    }

    /// **Flipping the rule before the first nudge re-lifts, and must not bake and must not record a
    /// step.** This is the sharpest bug available on this path and the test exists for it alone.
    ///
    /// `beginVectorLassoMove`'s first statement is `commitAllInteractiveState()`, which calls
    /// `commitVectorFloatIfNeeded()` and **bakes** the float, clearing the selection as it goes. So
    /// the tempting implementation — "just call begin again" — ships a Move that bakes on every tap of
    /// the picker, and after the first tap there is no loop left to lift against at all. The order has
    /// to be `cancelVectorFloat()` *then* `beginVectorLassoMove()`.
    ///
    /// The surviving **selection** is what catches the wrong order: a bake clears it (§5.6) and a
    /// cancel restores it verbatim. The unchanged **undo stack** is what catches a re-lift that
    /// records anything: a lift is not an edit, and a picker tap even less so.
    func testFlippingTheRuleBeforeTheFirstNudgeReLiftsWithoutBakingOrRecordingAStep() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let id = vector.elements[0].id
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(vector.elements.count, 2, "fixture precondition: Cut split the stroke")
        let stepsAtLift = manager.history.undoStack.count

        manager.setSelectionMembership(.touching)

        XCTAssertNotNil(manager.selection,
                        "the loop survived, so the float was cancelled and not baked")
        XCTAssertNotNil(manager.vectorFloat, "and a float is up again under the new rule")
        XCTAssertEqual(manager.history.undoStack.count, stepsAtLift,
                       "a picker tap is not an edit — nothing recorded, nothing consumed")
        XCTAssertEqual(vector.elements.count, 1, "the cut was undone: one stroke again")
        XCTAssertEqual(vector.elements[0].id, id, "and it is the original, not a re-split piece")
        XCTAssertEqual(manager.vectorFloat?.insideIDs, [id])
        XCTAssertEqual(manager.vectorFloat?.nudges, 0, "still un-nudged, so the picker stays live")
        XCTAssertEqual(vector.suppressedElementIDs, [id],
                       "and the new float's ids are the ones the flatten skips")
        XCTAssertEqual(manager.vectorFloat?.elementsBeforeLift.count, 1,
                       "the cancel's restore is what the next one puts back — the pre-lift list")

        manager.commitVectorFloatIfNeeded()
        XCTAssertEqual(vector.elements.count, 1, "and the bake leaves one stroke, not three")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)
    }

    /// **A rule that catches nothing keeps the float the artist already had, and says why.**
    ///
    /// Letting the re-lift fail would leave them with no float, no box and no bar after one tap on a
    /// segmented control, which reads as a crash. The previous rule is restored — guaranteed to
    /// succeed, because it succeeded a moment ago against the list the cancel has just put back — and
    /// the picker snaps back with the banner explaining it.
    func testFlippingToARuleThatCatchesNothingKeepsTheFloatAndSaysSo() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())

        manager.setSelectionMembership(.enclosed)

        XCTAssertEqual(manager.selectionMembership, .cutting, "the picker snaps back to the rule that works")
        XCTAssertNotNil(manager.vectorFloat, "and the artist keeps the piece they had lifted")
        XCTAssertEqual(vector.elements.count, 2, "cut exactly as it was")
        XCTAssertEqual(manager.vectorFloat?.insideIDs.count, 1)
        XCTAssertEqual(manager.notice?.code, "nothingWhollyInside",
                       "and is told why the picker did not stay where they put it")
    }

    /// **Enclosed catching nothing says so; an empty lasso still says nothing** (owner, 2026-08-28
    /// against LASSO_MOVE.md §5.9, and the two are not in conflict).
    ///
    /// The difference is what the artist can see. Over blank paper the reason is on screen already;
    /// over a loop full of ink it is the rule they picked, and a Move that does nothing and says
    /// nothing reads as a broken button.
    func testEnclosedCatchingNothingSaysSoAndABlankLoopStillStaysSilent() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        manager.setSelectionMembership(.enclosed)

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertFalse(manager.beginVectorLassoMove(), "no stroke lies completely inside the loop")
        XCTAssertNil(manager.vectorFloat)
        XCTAssertNotNil(manager.selection, "the loop stays on screen, ready to be redrawn")
        XCTAssertEqual(manager.notice?.code, "nothingWhollyInside")

        manager.notice = nil
        select(manager, layerIndex, loop(CGRect(x: 4, y: 44, width: 16, height: 16)))
        XCTAssertFalse(manager.beginVectorLassoMove(), "and bare paper still lifts nothing")
        XCTAssertNil(manager.notice,
                     "but says nothing about it — §5.9, where the artist can see the reason")
    }

    /// **The picker is live before anything has been selected at all**, which is the shape TODO item
    /// (23) moved it into: it lives in the Select panel now, and the rule is what the *next* loop will
    /// answer with. Asking an artist to draw a lasso before they may choose how it behaves has the
    /// order backwards, and the mode tabs beside it already work that way.
    ///
    /// There is no longer an "is it offered" question to ask. On the Move bar the picker was dropped
    /// for the whole-cel float, which has no loop; in the Select panel there is no float to ask about
    /// and the control is simply there.
    func testTheRuleCanBePickedBeforeAnythingIsSelected() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        XCTAssertNil(manager.selection, "fixture precondition: nothing lassoed yet")
        XCTAssertNil(manager.selectionMembershipUnavailableReason, "and the picker is live anyway")

        manager.setSelectionMembership(.touching)
        XCTAssertEqual(manager.selectionMembership, .touching, "the plain assignment arm took it")
        XCTAssertEqual(manager.displayedSelectionMembership, .touching)
    }

    /// **A whole-cel float has no loop, so changing the rule under it re-lifts nothing** — it is the
    /// plain assignment arm, kept from the days when the picker was dropped for that float entirely.
    func testChangingTheRuleUnderAWholeCelFloatIsAPlainAssignment() {
        let (manager, _, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        let ids = vector.elements.map(\.id)
        let steps = manager.history.undoStack.count

        manager.setSelectionMembership(.enclosed)

        XCTAssertEqual(manager.selectionMembership, .enclosed, "taken for the next lasso lift")
        XCTAssertNotNil(manager.vectorFloat, "and the whole-cel float is left exactly where it was")
        XCTAssertEqual(vector.elements.map(\.id), ids)
        XCTAssertEqual(manager.history.undoStack.count, steps)
    }

    /// **After the first nudge the model refuses the change**, for the reason
    /// `setSelectionMembership` states: a re-lift then would have to rewrite undo steps already on
    /// the stack against a display list that no longer matches them.
    ///
    /// **The caption that used to say so is gone with the Move bar's picker** (TODO item (23)). The
    /// picker lives in `SelectPanel`, which `DrawingView` does not show while anything floats
    /// (LASSO_MOVE.md §5.13), so this refusal has no control to grey out and no caption to carry. The
    /// guard stays in the setter, which is where `vectorFloatIsFreeform`'s rule says a guard belongs:
    /// one that lives only in a view is one a new call site removes.
    func testAfterTheFirstNudgeTheModelRefusesToChangeTheRule() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.nudgeVectorFloat(to: movedBy(manager, dx: 6, dy: 0))

        let elementsAfterNudge = vector.elements.map(\.id)
        let steps = manager.history.undoStack.count
        manager.setSelectionMembership(.touching)

        XCTAssertEqual(manager.selectionMembership, .cutting, "the setter refused")
        XCTAssertEqual(vector.elements.map(\.id), elementsAfterNudge, "and nothing was re-lifted")
        XCTAssertEqual(manager.history.undoStack.count, steps)
        XCTAssertEqual(manager.vectorFloat?.nudges, 1)
    }

    /// **A pixel layer shows Cut fixed and says why** — and the reason is a real limit rather than a
    /// policy: `PixelOps.maskedPiece` is Move's cut there, `PixelOps.clear` is Clear's, a recolour
    /// refuses outright, and a raster cel has no elements for "whole or partial" to be about.
    ///
    /// **The subject is the layer, not the float** (TODO item (23)): the picker is now asked in the
    /// Select panel before anything has been lifted. This asserts both, on one manager, so the two
    /// readings cannot drift — a raster float can only ever have come off a raster layer.
    ///
    /// It is asked of the layer rather than of whatever is floating, which is why it can answer at all
    /// with nothing lifted.
    func testAPixelLayerShowsCutFixedAndSaysWhy() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 10, y: 10, width: 20, height: 20)))
        manager.selectionMembership = .touching

        XCTAssertEqual(manager.selectionMembershipUnavailableReason,
                       "A pixel layer can only cut at the selection.",
                       "asked of the layer, with nothing selected and nothing floating")
        XCTAssertEqual(manager.displayedSelectionMembership, .cutting,
                       "and never shown holding a setting nothing on this layer obeys")

        manager.selection = Selection(path: CGPath(rect: CGRect(x: 8, y: 8, width: 24, height: 24), transform: nil),
                                      bounds: CGRect(x: 8, y: 8, width: 24, height: 24),
                                      layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id)
        manager.beginMove()
        XCTAssertNotNil(manager.floatingPiece, "fixture precondition: something lifted")

        XCTAssertEqual(manager.selectionMembershipUnavailableReason,
                       "A pixel layer can only cut at the selection.",
                       "and the float agrees with the layer it came off")

        manager.setSelectionMembership(.enclosed)
        XCTAssertEqual(manager.selectionMembership, .touching, "and nothing writes through it")
    }

    /// **A value layer gets its own sentence**, because it is a different refusal wearing the same
    /// shape: `Layer.hasNoDrawingSurface` means no pixels *and* no elements, so "a pixel layer can
    /// only cut at the selection" would name a mechanism that is not there either.
    func testAValueLayerRefusesTheRuleInItsOwnWords() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.layers[0].kind = .value

        XCTAssertEqual(manager.selectionMembershipUnavailableReason,
                       "A value layer holds nothing a lasso can catch.")
        XCTAssertEqual(manager.displayedSelectionMembership, .cutting)
    }

    /// **One rule, read by both tools — which is the whole of TODO item (23).**
    ///
    /// The owner, 2026-08-29: *"i feel like it would be better in select menu because i want it to
    /// affect recolour."* Membership was `lassoMoveMembership` and lived on the Move bar; it is
    /// `selectionMembership` and lives in the Select panel, and this asserts the consequence rather
    /// than the rename — the same loop, the same setting, the same answer to "what did it catch",
    /// whichever of the two doors asks.
    ///
    /// Asserted on **one** manager and with **one** `setSelectionMembership` call on purpose: two
    /// fixtures each setting their own value would still pass if the two tools read two properties.
    func testTheSameRuleGovernsBothARecolourAndALift() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 58, y: 20), size: 6))
        let originalID = vector.elements[0].id
        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        manager.setSelectionMembership(.touching)

        manager.brushColor = picked(1, 0, 0)
        manager.recolorSelection()
        XCTAssertEqual(vector.elements.count, 1, "Touching recoloured the straddling stroke whole")
        XCTAssertEqual(vector.elements[0].id, originalID, "and cut nothing")

        select(manager, layerIndex, loop(CGRect(x: 30, y: 2, width: 30, height: 60)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        XCTAssertEqual(vector.elements.count, 1, "and the very same setting lifts it whole too")
        XCTAssertEqual(manager.vectorFloat?.insideIDs, [originalID],
                       "one property, two consumers — neither grew its own copy")
    }

    // MARK: - Helpers

    /// The float's ink **as it currently sits in the document**, expressed in the drawn box's own
    /// local units and paired with the half-width that wraps it there. The oracle
    /// `assertTheBoxHugs` measures against.
    ///
    /// The inverse projection is written out here rather than called into `ObjectTransformFrame`, so
    /// a change made to both at once cannot pass. `pad` is anisotropic for the reason the fit's own
    /// is: the ink's footprint is a disc in *canvas* space — `mapping(_:throughStretch:)` scales a
    /// stroke's width by `sqrt(|det|)` precisely to keep it one — and the box's local units are not
    /// square once it has been stretched.
    private func inkInBoxUnits(_ vector: VectorCanvas, _ float: VectorFloat,
                               _ frame: ObjectTransformFrame) -> [(u: CGPoint, pad: CGPoint)] {
        let s = ObjectTransformFrame.axisScales(scale: frame.transform.scale, aspect: frame.aspect)
        let toCanvas = vector.transform
        let canvasScale = hypot(toCanvas.a, toCanvas.b)
        let r = -(frame.transform.rotation + frame.boxAngle)
        func boxLocal(_ p: CGPoint) -> CGPoint {
            let dx = p.x - frame.transform.position.x, dy = p.y - frame.transform.position.y
            return CGPoint(x: (dx * cos(r) - dy * sin(r)) / s.x - frame.contentOffset.x,
                           y: (dx * sin(r) + dy * cos(r)) / s.y - frame.contentOffset.y)
        }
        var result: [(u: CGPoint, pad: CGPoint)] = []
        for element in vector.elements where float.insideIDs.contains(element.id) {
            var points: [CGPoint] = []
            var reach: CGFloat = 0
            switch element {
            case .stroke(let stroke):
                points = stroke.samples.map { CGPoint(x: $0.x, y: $0.y) }
                reach = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
            case .fill(let fill):
                guard let path = fill.cgPath else { continue }
                path.applyWithBlock { pointer in
                    switch pointer.pointee.type {
                    case .moveToPoint, .addLineToPoint:
                        points.append(pointer.pointee.points[0])
                    case .addQuadCurveToPoint:
                        points.append(pointer.pointee.points[0])
                        points.append(pointer.pointee.points[1])
                    case .addCurveToPoint:
                        for i in 0..<3 { points.append(pointer.pointee.points[i]) }
                    case .closeSubpath:
                        break
                    @unknown default:
                        break
                    }
                }
            case .text(let text):
                points = text.frame.corners
            case .image:
                XCTFail("this oracle does not model a placed image")
            }
            let pad = CGPoint(x: reach * canvasScale / s.x, y: reach * canvasScale / s.y)
            result += points.map { (boxLocal($0.applying(toCanvas)), pad) }
        }
        return result
    }

    /// **All four edges of the drawn box touch the ink, and none of it sticks out.** Stated as four
    /// separate equalities rather than as two extents, because a box of the right *size* in the wrong
    /// *place* satisfies any assertion made on width and height.
    private func assertTheBoxHugs(_ vector: VectorCanvas, _ float: VectorFloat,
                                  _ frame: ObjectTransformFrame, accuracy: CGFloat,
                                  _ note: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let ink = inkInBoxUnits(vector, float, frame)
        guard !ink.isEmpty else {
            return XCTFail("no ink to hug — \(note)", file: file, line: line)
        }
        let edges = [("left", ink.map { $0.u.x - $0.pad.x }.min()!, -frame.contentSize.width / 2),
                     ("right", ink.map { $0.u.x + $0.pad.x }.max()!, frame.contentSize.width / 2),
                     ("top", ink.map { $0.u.y - $0.pad.y }.min()!, -frame.contentSize.height / 2),
                     ("bottom", ink.map { $0.u.y + $0.pad.y }.max()!, frame.contentSize.height / 2)]
        for (which, measured, expected) in edges {
            XCTAssertEqual(measured, expected, accuracy: accuracy,
                           "the \(which) edge sits at \(expected) and the ink reaches \(measured) "
                           + "— \(note)", file: file, line: line)
        }
    }

    /// The pose a **Freeform** corner drag that grows the box by `(fx, fy)` on its own two axes
    /// writes, from where the float is now — `ObjectTransformDrag`'s stretched arm stated as its two
    /// outputs, so a test says what the artist did rather than where their finger was.
    private func stretched(_ manager: CanvasManager, x fx: CGFloat, y fy: CGFloat)
        -> (transform: LayerTransform, aspect: CGFloat) {
        guard let frame = manager.vectorFloat?.frame else { return (.identity, 1) }
        let base = ObjectTransformFrame.axisScales(scale: frame.transform.scale, aspect: frame.aspect)
        let sx = base.x * fx, sy = base.y * fy
        var transform = frame.transform
        transform.scale = sqrt(sx * sy)
        return (transform, sx / sy)
    }

    /// The box transform a drag of `(dx, dy)` canvas points produces, from where the float is now.
    private func movedBy(_ manager: CanvasManager, dx: CGFloat, dy: CGFloat) -> LayerTransform {
        guard var transform = manager.vectorFloat?.frame.transform else { return .identity }
        transform.position = CGPoint(x: transform.position.x + dx, y: transform.position.y + dy)
        return transform
    }

    /// The box transform a corner drag to `k`× produces, from where the float is now — the shape
    /// `ObjectTransformDrag`'s corner arm writes (`start.scale * (currentDistance / startDistance)`).
    private func scaledBy(_ manager: CanvasManager, _ k: CGFloat) -> LayerTransform {
        guard var transform = manager.vectorFloat?.frame.transform else { return .identity }
        transform.scale *= k
        return transform
    }

    /// The box transform the green knob produces after turning it `radians` — `ObjectTransformDrag`'s
    /// rotation arm, `start.rotation + (currentAngle - startAngle)`.
    private func turnedBy(_ manager: CanvasManager, _ radians: CGFloat) -> LayerTransform {
        guard var transform = manager.vectorFloat?.frame.transform else { return .identity }
        transform.rotation += radians
        return transform
    }

    /// Records where every dab landed and how big it was, so a claim about the *walk* is measured at
    /// the level it is made rather than inferred from pixels.
    private final class RecordingDabTarget: DabTarget {
        private(set) var dabs: [(point: CGPoint, radius: CGFloat)] = []
        func beginStroke() {}
        func endStroke() {}
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            dabs.append((point, radius))
        }
    }

    /// Mirrors `VectorCanvas.stamp(stroke:into:isEraser:)`, which is private to that class. **The
    /// lattice arm is the load-bearing half here**: a cut piece draws from its parent's samples
    /// through a `visibleRange`, so walking `stroke.samples` instead would measure a walk the
    /// renderer never performs.
    private func dabs(of stroke: VectorStroke) -> [(point: CGPoint, radius: CGFloat)] {
        let target = RecordingDabTarget()
        let lattice = stroke.lattice.flatMap { $0.range == nil ? nil : $0 }
        let source = lattice?.samples ?? stroke.samples
        BrushStamper.stampStroke(into: target,
                                 samples: source.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) },
                                 brush: stroke.brush, color: stroke.uiColor, brushSize: stroke.size,
                                 brushOpacity: stroke.opacity, isEraser: stroke.composite == .erase,
                                 seed: BrushStamper.seed(for: lattice?.seedID ?? stroke.id),
                                 visibleRange: lattice?.range)
        return target.dabs
    }

    /// How many pixels carry ink — the conservation quantity a rotation preserves and a lost element
    /// does not.
    private func opaquePixelCount(_ vector: VectorCanvas) -> Int {
        guard let cg = vector.render().cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return 0 }
        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 128 ? 1 : 0) }
    }

    private func isOpaque(_ vector: VectorCanvas, at point: CGPoint) -> Bool {
        guard let cg = vector.render().cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return false }
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return false }
        return bytes[(y * cg.width + x) * 4 + 3] > 128
    }
}
