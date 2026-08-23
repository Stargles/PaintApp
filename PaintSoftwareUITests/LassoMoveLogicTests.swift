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
            ("undo with zero nudges", { $0.undo() })
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
    func testAZeroDeltaNudgeChangesNoSampleAndNoPixelOnATransformedLayer() {
        for transform in [CGAffineTransform.identity,
                          CGAffineTransform(translationX: 7, y: -3).scaledBy(x: 1.4, y: 1.4)] {
            let (manager, layerIndex, vector) = fixture()
            vector.setTransform(transform)
            vector.addStroke(stroke(from: CGPoint(x: 6, y: 22), to: CGPoint(x: 40, y: 22), size: 5))
            vector.addStroke(stroke(from: CGPoint(x: 6, y: 34), to: CGPoint(x: 40, y: 34), size: 5))
            // The loop is CANVAS space; the stored geometry is LOCAL. On a transformed layer the two
            // are different rectangles, and skipping the mapping is silently wrong here and only here.
            let localLoop = CGRect(x: 20, y: 4, width: 40, height: 50)
            let canvasLoop = localLoop.applying(transform)
            // Both taken *before* the lift: after it the moved ids are suppressed, so the render is
            // the hole rather than the drawing, and comparing against that would assert nothing.
            let pixelsBefore = cgImage(vector)
            select(manager, layerIndex, loop(canvasLoop))
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

    /// The ants **travel with the piece** and clear **at the bake**, not at the lift.
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

    // MARK: - Helpers

    /// The box transform a drag of `(dx, dy)` canvas points produces, from where the float is now.
    private func movedBy(_ manager: CanvasManager, dx: CGFloat, dy: CGFloat) -> LayerTransform {
        guard var transform = manager.vectorFloat?.frame.transform else { return .identity }
        transform.position = CGPoint(x: transform.position.x + dx, y: transform.position.y + dy)
        return transform
    }

    private func isOpaque(_ vector: VectorCanvas, at point: CGPoint) -> Bool {
        guard let cg = vector.render().cgImage, let bytes = CanvasFixture.rgbaBytes(cg) else { return false }
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return false }
        return bytes[(y * cg.width + x) * 4 + 3] > 128
    }
}
