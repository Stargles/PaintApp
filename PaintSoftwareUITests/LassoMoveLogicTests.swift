import XCTest
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

    /// The opaque bounding box of what a canvas actually draws — the question "did the *ink* move",
    /// which is not the same question as "did the samples move". See
    /// `testANudgeMovesTheRenderedInkAndNotOnlyTheSamples`.
    private func inkBounds(_ vector: VectorCanvas) -> CGRect? {
        PixelOps.opaqueContentBounds(vector.render())
    }

    // MARK: - The one that would silently lose artwork

    /// **Every way a float can end leaves nothing suppressed and nothing dropped.**
    ///
    /// Six paths, and each is a different door: the artist taps Move again; they undo before nudging;
    /// they switch tool or panel; they change layer; they change frame; they press undo after a
    /// nudge. A leak on any one of them is artwork that is in the document and renders nowhere.
    ///
    /// Watched failing with `commitVectorFloatIfNeeded`'s `suppressedElementIDs = []` removed — four
    /// of the six doors went red at once: *commit: 2 element(s) still suppressed after commit*, and
    /// the same for tool switch, layer change and frame change.
    func testEveryTeardownPathLeavesNothingSuppressedAndNothingDropped() {
        let paths: [(name: String, act: (CanvasManager) -> Void)] = [
            ("commit", { $0.commitVectorFloatIfNeeded() }),
            ("cancel", { $0.cancelVectorFloat() }),
            ("tool switch", { $0.commitAllInteractiveState() }),
            ("layer change", { $0.currentLayerIndex = 0 }),
            ("frame change", { manager in
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
            }),
            ("undo with zero nudges", { $0.undo() }),
            // The two handle kinds the box gained in stage 1. A scale and a rotate reach the same
            // teardown as a move, and this is the artwork-loss test, so they belong in it.
            ("commit after a scale", { manager in
                manager.nudgeVectorFloat(to: {
                    guard var t = manager.vectorFloat?.frame.transform else { return .identity }
                    t.scale *= 1.8
                    return t
                }())
                manager.commitVectorFloatIfNeeded()
            }),
            ("undo after a rotate", { manager in
                manager.nudgeVectorFloat(to: {
                    guard var t = manager.vectorFloat?.frame.transform else { return .identity }
                    t.rotation += 0.5
                    return t
                }())
                manager.undo()
            })
        ]
        for path in paths {
            let (manager, layerIndex, vector) = fixture()
            vector.addStroke(stroke(from: CGPoint(x: 8, y: 20), to: CGPoint(x: 56, y: 20)))
            vector.addStroke(stroke(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 30, y: 44)))
            let idsBefore = Set(vector.elements.map(\.id))
            select(manager, layerIndex, loop(CGRect(x: 24, y: 4, width: 32, height: 56)))
            XCTAssertTrue(manager.beginVectorLassoMove(), "\(path.name): the lift should have caught something")

            path.act(manager)

            XCTAssertTrue(vector.suppressedElementIDs.isEmpty,
                          "\(path.name): \(vector.suppressedElementIDs.count) element(s) still suppressed after \(path.name)")
            XCTAssertNil(manager.vectorFloat, "\(path.name): the float outlived its teardown")
            // Nothing dropped: every id that was there before the lift is either still there, or has
            // been replaced by pieces — and either way the list can never be *shorter* than it was.
            let idsAfter = Set(vector.elements.map(\.id))
            XCTAssertGreaterThanOrEqual(idsAfter.count, idsBefore.count,
                                        "\(path.name): the display list lost elements")
            XCTAssertFalse(vector.elements.isEmpty, "\(path.name): the display list was emptied")
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
        manager.updateFloatingTransform(dragged)
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
        XCTAssertNil(manager.mirrorUnavailableReason, "strokes and fills mirror exactly")

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

    /// **Mirror refuses, out loud, when the lassoed piece carries a placed image or a text box.**
    ///
    /// Neither is expressible: an image's whole placement is a `LayerTransform` with no flip in it,
    /// and a text frame is four ordered corners that `TextFrame.Basis` reads as a frame rather than as
    /// a shape. Carrying them through the reflection anyway is not a rounding error — `theta` becomes
    /// `atan2` of a map that turns the plane over, and the photo would come back rotated a half turn
    /// instead of mirrored. So the button is off and the bar says why, which is the difference between
    /// a disabled control and a control that does nothing.
    func testMirrorIsRefusedAndSaysWhyWhenThePieceCarriesAnImageOrText() {
        for kind in ["image", "text"] {
            let (manager, layerIndex, vector) = fixture()
            vector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
            if kind == "image" {
                vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                                   rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                                   size: CGSize(width: 6, height: 6)),
                                                   transform: LayerTransform(position: CGPoint(x: 30, y: 34),
                                                                             scale: 1, rotation: 0)))
            } else {
                var recipe = TextRecipe(string: "hi")
                recipe.typography.pointSize = 12
                vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                                    frame: TextFrame(origin: CGPoint(x: 30, y: 34),
                                                                     size: CGSize(width: 10, height: 6))))
            }
            select(manager, layerIndex, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
            XCTAssertTrue(manager.beginVectorLassoMove(), "\(kind): the lift should have caught both")
            let samplesBefore = vector.elements.compactMap(\.stroke).map(\.samples)
            let stepsBefore = manager.history.undoStack.count

            XCTAssertNotNil(manager.mirrorUnavailableReason, "\(kind): the bar has to have something to say")
            manager.mirrorFloating(horizontal: true)

            XCTAssertEqual(manager.vectorFloat?.mirror, CGAffineTransform.identity, "\(kind): and the press changes nothing")
            XCTAssertEqual(manager.history.undoStack.count, stepsBefore,
                           "\(kind): a refused button spends no undo step either")
            let samplesAfter = vector.elements.compactMap(\.stroke).map(\.samples)
            for (before, after) in zip(samplesBefore, samplesAfter) {
                for (a, b) in zip(before, after) { XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "\(kind)") }
            }
        }
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
    func testTheTransformModesAreFreeformUniformAndDistortWithNoWarp() {
        XCTAssertEqual(TransformMode.allCases.map(\.rawValue), ["freeform", "uniform", "distort"])
        XCTAssertEqual(TransformMode.allCases.filter { !$0.isImplemented }, [.distort],
                       "and Distort is the only one the bar still has to caption")
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

    /// **Freeform refuses, out loud, when the piece carries a placed image or a text box** — the
    /// Mirror pattern, applied to the neighbouring impossibility. An image's placement *is* a
    /// `LayerTransform`, which has one scale and no second axis any more than it has a flip; a text
    /// frame's `Basis` reads four ordered corners as a layout size.
    ///
    /// Both halves matter and they are separate guards: the bar disables the picker from the reason,
    /// and `vectorFloatIsFreeform` refuses the drag even if `transformMode` arrived already set to
    /// `.freeform` from a raster Move three gestures ago — which it can, since the mode is shared
    /// with the raster tier and outlives the piece that chose it.
    func testFreeformIsRefusedAndSaysWhyWhenThePieceCarriesAnImageOrText() {
        for kind in ["image", "text"] {
            let (manager, layerIndex, vector) = fixture()
            vector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
            if kind == "image" {
                vector.addImage(VectorImageElement(image: CanvasFixture.solidImage(.green,
                                                                                   rect: CGRect(x: 0, y: 0, width: 6, height: 6),
                                                                                   size: CGSize(width: 6, height: 6)),
                                                   transform: LayerTransform(position: CGPoint(x: 30, y: 34),
                                                                             scale: 1, rotation: 0)))
            } else {
                var recipe = TextRecipe(string: "hi")
                recipe.typography.pointSize = 12
                vector.upsertText(VectorTextElement(id: UUID(), recipe: recipe,
                                                    frame: TextFrame(origin: CGPoint(x: 30, y: 34),
                                                                     size: CGSize(width: 10, height: 6))))
            }
            select(manager, layerIndex, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
            XCTAssertTrue(manager.beginVectorLassoMove(), "\(kind): the lift should have caught both")

            manager.setTransformMode(.freeform)
            XCTAssertNotNil(manager.freeformUnavailableReason, "\(kind): the bar has to have something to say")
            XCTAssertFalse(manager.vectorFloatIsFreeform,
                           "\(kind): and the drag refuses even with the mode already lit")
        }

        // The same predicate answers the other way for what a drawing is actually made of.
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 26, y: 24), to: CGPoint(x: 38, y: 24), size: 3))
        vector.addFill(VectorFillElement(path: CGPath(rect: CGRect(x: 26, y: 30, width: 10, height: 5),
                                                      transform: nil),
                                         color: black(), opacity: 1, evenOddFill: false))
        select(manager, layerIndex, loop(CGRect(x: 18, y: 16, width: 32, height: 30)))
        XCTAssertTrue(manager.beginVectorLassoMove())
        manager.setTransformMode(.freeform)
        XCTAssertNil(manager.freeformUnavailableReason, "strokes and fills stretch exactly")
        XCTAssertTrue(manager.vectorFloatIsFreeform)
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
        manager.nudgeVectorFloat(to: pose.transform, aspect: pose.aspect)
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, false,
                       "and a stretch hands the display back to the layer's own render")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty)

        // The next drag re-arms it, and against the pose the bitmap will actually be rendered at —
        // both halves, or the stretch already in the bitmap is applied to it a second time.
        manager.beginVectorFloatDrag()
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, true)
        XCTAssertEqual(manager.vectorFloat?.latchedAspect ?? 0, manager.vectorFloat?.frame.aspect ?? -1)
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

    // MARK: - Helpers

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
