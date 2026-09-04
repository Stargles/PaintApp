import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for turning a recipe into pixels.
///
/// Three things are being pinned here, in descending order of how expensive they are to discover
/// later:
///
/// 1. **Isolation.** Keyframe A's eraser must not reach keyframe C's ink. This is the one
///    correctness property the renderer exists for; `testAnEraserInKeyframeADoesNot…`
///    carries a control case that shows the naive alternative genuinely fails, so the test is not
///    quietly passing for the wrong reason.
/// 2. **The endpoints.** `t = 0` reproduces keyframe A and `t = 1` reproduces keyframe C, as pixels,
///    through the general path rather than a short-circuit. `testAnInBetweenDiffersFromBoth…` is what
///    stops that pair from being satisfied by an evaluator that never moves anything.
/// 3. **Determinism.** Same recipe and same `t` → the same bytes, so a scrub back and forth does not
///    shimmer.
///
/// Renders are compared with `RasterVectorParity.report`, reused rather than reimplemented: it
/// normalises both images through one 8-bit deviceRGB context, which is the only thing that makes a
/// byte comparison between two differently-produced `UIImage`s mean anything.
final class InterpolationRenderLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let canvasSize = CGSize(width: 160, height: 160)

    /// Fixed ids everywhere. Dab scatter and rotation jitter are seeded from a stroke's id
    /// (`BrushStamper.seed(for:)`), so a fresh `UUID()` per run would make "identical bytes" a
    /// statement about luck.
    private enum ID {
        static let layer = UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!
        static let celA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        static let celC = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        static let group = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
        static let paintA = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        static let paintC = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        static let eraser = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
        static let localEdit = UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!
        static let fill = UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!
    }

    private static let celARef = CelRef(layerID: ID.layer, celID: ID.celA)
    private static let celCRef = CelRef(layerID: ID.layer, celID: ID.celC)

    /// Hard-edged, fully opaque, no jitter. Every assertion below is about *where* ink landed, and a
    /// soft or textured brush turns each of them into a question about a gradient's tail instead.
    private static let brush = BrushLibrary.hardRound

    private func stroke(_ points: [CGPoint], id: UUID, size: CGFloat = 14,
                        color: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                        composite: StrokeComposite = .paint,
                        visibilityThreshold: CGFloat? = nil,
                        sampleVisibilityThresholds: [Int: CGFloat]? = nil) -> VectorStroke {
        VectorStroke(id: id, brush: Self.brush, color: color, size: size, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly),
                     composite: composite, lattice: nil, motionGroupID: nil,
                     visibilityThreshold: visibilityThreshold,
                     sampleVisibilityThresholds: sampleVisibilityThresholds)
    }

    /// A horizontal bar of ink at `y`, spanning `x`.
    private func bar(y: CGFloat, from x0: CGFloat = 20, to x1: CGFloat = 140, id: UUID,
                     size: CGFloat = 14, composite: StrokeComposite = .paint) -> VectorElement {
        .stroke(stroke([CGPoint(x: x0, y: y), CGPoint(x: x1, y: y)], id: id, size: size,
                       composite: composite))
    }

    /// A recipe over two references, with one motion group whose lattice moves by `motion`.
    ///
    /// Every stroke in these fixtures is *untagged*, which is deliberate: it exercises the rule that
    /// content with no `motionGroupID` rides the first binding, and that rule is what makes Phase 4's
    /// single automatic whole-layer group work at all.
    private func recipe(motion: (Lattice) -> Lattice,
                        a: [VectorElement], c: [VectorElement],
                        localEdits: [LocalEdit] = []) -> InterpolationRecipe {
        // Covering the whole canvas rather than the content's bounding box, for two reasons: a
        // fixture whose only element is a fill has no stroke samples to bound, and a grid pinned to
        // the canvas keeps every vertex on an exact multiple of the cell size — which is what lets
        // the endpoint tests below compare renders at zero tolerance rather than "close enough".
        let rest = Lattice(covering: [.zero, CGPoint(x: Self.canvasSize.width, y: Self.canvasSize.height)],
                           targetCellSize: 40, padding: 1)
        return InterpolationRecipe(
            references: [InterpolationReference(cels: [Self.celARef]),
                         InterpolationReference(cels: [Self.celCRef])],
            t: 0,
            mode: .generate,
            groups: [MotionGroupBinding(groupID: ID.group, lattices: [rest, motion(rest)])],
            localEdits: localEdits)
    }

    private func content(a: [VectorElement], c: [VectorElement]) -> InterpolationEvaluator.ContentProvider {
        { ref in
            switch ref {
            case Self.celARef: return a
            case Self.celCRef: return c
            default: return []
            }
        }
    }

    /// Rigid translation of the whole lattice. The simplest motion that is unmistakably *motion*.
    ///
    /// A whole cell's worth by default, and that is not laziness: it leaves every deformed vertex on
    /// an exact binary value, so the inverse bilinear the backward set goes through round-trips to
    /// the bit and `t = 1` can be asserted at zero tolerance. An off-grid offset would be just as
    /// correct and would make that assertion a claim about floating point instead.
    private static func translated(by dx: CGFloat = 40) -> (Lattice) -> Lattice {
        { $0.withVertices($0.vertices.map { CGPoint(x: $0.x + dx, y: $0.y) }) }
    }

    /// No motion at all — same lattice at both keyframes. Used where the assertion is about
    /// compositing and a moving lattice would only add noise.
    private static let still: (Lattice) -> Lattice = { $0 }

    private func render(_ recipe: InterpolationRecipe, at t: CGFloat,
                        a: [VectorElement], c: [VectorElement],
                        quality: RenderQuality = .full) -> UIImage? {
        InterpolationEvaluator.render(recipe: recipe, at: t, size: Self.canvasSize,
                                      content: content(a: a, c: c), quality: quality)
    }

    private func flat(_ elements: [VectorElement], quality: RenderQuality = .full) -> UIImage {
        VectorCanvas(size: Self.canvasSize, elements: elements).render(quality: quality)
    }

    /// Premultiplied alpha at one canvas point.
    private func alpha(_ image: UIImage, at point: CGPoint) -> Int {
        guard let bytes = RasterVectorParity.premultipliedBytes(of: image, size: Self.canvasSize) else {
            return -1
        }
        let index = (Int(point.y) * Int(Self.canvasSize.width) + Int(point.x)) * 4
        return Int(bytes[index + 3])
    }

    // MARK: - The endpoints

    func testEvaluatingAtZeroIsPixelIdenticalToKeyframeA() throws {
        let a = [bar(y: 60, id: ID.paintA)]
        let c = [bar(y: 100, id: ID.paintC)]
        let recipe = recipe(motion: Self.translated(), a: a, c: c)

        let evaluated = try XCTUnwrap(render(recipe, at: 0, a: a, c: c))
        let report = try XCTUnwrap(RasterVectorParity.report(raster: flat(a), vector: evaluated,
                                                            size: Self.canvasSize))
        XCTAssertTrue(report.isExact, "t = 0 must reproduce keyframe A: \(report.diagnostic)")
    }

    func testEvaluatingAtOneIsPixelIdenticalToKeyframeC() throws {
        let a = [bar(y: 60, id: ID.paintA)]
        let c = [bar(y: 100, id: ID.paintC)]
        let recipe = recipe(motion: Self.translated(), a: a, c: c)

        let evaluated = try XCTUnwrap(render(recipe, at: 1, a: a, c: c))
        let report = try XCTUnwrap(RasterVectorParity.report(raster: flat(c), vector: evaluated,
                                                            size: Self.canvasSize))
        XCTAssertTrue(report.isExact, "t = 1 must reproduce keyframe C: \(report.diagnostic)")
    }

    /// The test that stops the two above from being satisfied by an evaluator that never moves
    /// anything: at an interior `t` the frame must be neither keyframe.
    func testAnInBetweenDiffersFromBothKeyframes() throws {
        let a = [bar(y: 60, id: ID.paintA)]
        let c = [bar(y: 100, id: ID.paintC)]
        let recipe = recipe(motion: Self.translated(), a: a, c: c)

        let middle = try XCTUnwrap(render(recipe, at: 0.5, a: a, c: c))
        let versusA = try XCTUnwrap(RasterVectorParity.report(raster: flat(a), vector: middle,
                                                             size: Self.canvasSize))
        let versusC = try XCTUnwrap(RasterVectorParity.report(raster: flat(c), vector: middle,
                                                             size: Self.canvasSize))
        XCTAssertFalse(versusA.isExact, "t = 0.5 must not be keyframe A")
        XCTAssertFalse(versusC.isExact, "t = 0.5 must not be keyframe C")
    }

    /// Motion, specifically — not merely a cross-fade. A's bar sits at `y = 60` and the lattice
    /// translates in `x`, so at an interior `t` there must be ink to the right of where A's bar ends.
    func testTheLatticeActuallyCarriesKeyframeAsContent() throws {
        let a = [bar(y: 60, from: 20, to: 100, id: ID.paintA)]
        let c: [VectorElement] = []
        let recipe = recipe(motion: Self.translated(), a: a, c: c)

        XCTAssertEqual(alpha(try XCTUnwrap(render(recipe, at: 0, a: a, c: c)),
                             at: CGPoint(x: 130, y: 60)), 0,
                       "Setup: nothing is at x = 130 at t = 0")
        XCTAssertGreaterThan(alpha(try XCTUnwrap(render(recipe, at: 0.9, a: a, c: c)),
                                   at: CGPoint(x: 130, y: 60)), 0,
                             "A's bar should have been carried right by the lattice")
    }

    // MARK: - Isolation (PLAN §5.6) — the phase's reason for existing

    /// Keyframe A holds a bar and an eraser through its middle; keyframe C holds a bar in exactly the
    /// place A's eraser punches. At an in-between, C's bar must survive.
    ///
    /// The control half is the point. Concatenating the two sets into one display list is the obvious
    /// implementation and it is *wrong*: this asserts that the naive list really does lose C's ink,
    /// so the passing half is evidence about isolation rather than about the scene being too easy.
    func testAnEraserInKeyframeADoesNotPunchKeyframeCsStrokes() throws {
        let hole = CGPoint(x: 80, y: 80)
        let a = [bar(y: 80, id: ID.paintA),
                 bar(y: 80, from: 60, to: 100, id: ID.eraser, size: 30, composite: .erase)]
        let c = [bar(y: 80, id: ID.paintC)]
        let recipe = recipe(motion: Self.still, a: a, c: c)

        let isolated = try XCTUnwrap(render(recipe, at: 0.5, a: a, c: c))
        XCTAssertGreaterThan(alpha(isolated, at: hole), 0,
                             "C's stroke must survive A's eraser")

        // Control: the same content in one list, which is what isolation exists to prevent.
        let concatenated = flat(c + a)
        XCTAssertEqual(alpha(concatenated, at: hole), 0,
                       "Control: concatenating really does let A's eraser eat C's stroke")
    }

    /// An eraser that exists at A and not at C. It needs no visibility threshold and no
    /// eraser-specific code: it lives in the forward set, and that set's weight takes it away.
    func testAnEraserPresentOnlyInKeyframeAFadesOutProgressively() throws {
        let hole = CGPoint(x: 80, y: 80)
        let a = [bar(y: 80, id: ID.paintA),
                 bar(y: 80, from: 60, to: 100, id: ID.eraser, size: 30, composite: .erase)]
        let c = [bar(y: 80, id: ID.paintC)]
        let recipe = recipe(motion: Self.still, a: a, c: c)

        let opacities = try [0, 0.25, 0.5, 0.75, 1].map { t in
            alpha(try XCTUnwrap(render(recipe, at: CGFloat(t), a: a, c: c)), at: hole)
        }
        XCTAssertEqual(opacities.first, 0, "At t = 0 the hole is A's, and fully punched")
        XCTAssertEqual(opacities.last, 255, "By t = 1 it is C's bar, intact")
        for (earlier, later) in zip(opacities, opacities.dropFirst()) {
            XCTAssertGreaterThan(later, earlier,
                                 "The hole must close progressively, not pop: \(opacities)")
        }
    }

    /// A local edit is not a keyframe's content, so it is not cross-faded — and an `.erase` local
    /// edit has to reach *both* keyframes' ink, which is only true if it is drawn after the blend.
    func testAnEraserDrawnAtTheInBetweenPunchesBothKeyframes() throws {
        let hole = CGPoint(x: 80, y: 80)
        let a = [bar(y: 80, id: ID.paintA)]
        let c = [bar(y: 80, id: ID.paintC)]
        let edit = LocalEdit(id: ID.localEdit,
                             stroke: stroke([CGPoint(x: 60, y: 80), CGPoint(x: 100, y: 80)],
                                            id: ID.eraser, size: 30, composite: .erase),
                             groupID: nil)
        let withoutEdit = recipe(motion: Self.still, a: a, c: c)
        let withEdit = recipe(motion: Self.still, a: a, c: c, localEdits: [edit])

        // 192, not 255: two opaque coincident drawings cross-faded at ½ compose to ¾ alpha
        // (½ + ½·½). That washing-out at interior `t` is a known cost of a cross-fade fallback,
        // not this test's subject, so it only asserts ink.
        XCTAssertGreaterThan(alpha(try XCTUnwrap(render(withoutEdit, at: 0.5, a: a, c: c)), at: hole), 0,
                             "Setup: both keyframes have ink here")
        XCTAssertEqual(alpha(try XCTUnwrap(render(withEdit, at: 0.5, a: a, c: c)), at: hole), 0,
                       "A local eraser must punch the blended result, not one keyframe's copy")
    }

    // MARK: - Visibility

    func testAStrokeIsNotDrawnBelowItsVisibilityThreshold() throws {
        let probe = CGPoint(x: 80, y: 40)
        let late = VectorElement.stroke(stroke([CGPoint(x: 20, y: 40), CGPoint(x: 140, y: 40)],
                                               id: ID.paintA, visibilityThreshold: 0.6))
        let a = [late]
        let c: [VectorElement] = []
        let recipe = recipe(motion: Self.still, a: a, c: c)

        XCTAssertEqual(alpha(try XCTUnwrap(render(recipe, at: 0.5, a: a, c: c)), at: probe), 0,
                       "t below τ: nothing drawn")
        XCTAssertGreaterThan(alpha(try XCTUnwrap(render(recipe, at: 0.6, a: a, c: c)), at: probe), 0,
                             "t at τ: drawn")
    }

    /// Per-sample thresholds are what let a stroke vanish along its length rather than popping. The
    /// far end carries a later τ, so at an intermediate `t` the near end is there and the far end is
    /// not.
    func testPerSampleThresholdsRevealAStrokeAlongItsLength() throws {
        let near = CGPoint(x: 30, y: 40)
        let far = CGPoint(x: 130, y: 40)
        let samples = stride(from: CGFloat(20), through: 140, by: 20).map { CGPoint(x: $0, y: 40) }
        let thresholds = Dictionary(uniqueKeysWithValues:
            samples.indices.map { ($0, CGFloat($0) / CGFloat(samples.count - 1)) })
        let a = [VectorElement.stroke(stroke(samples, id: ID.paintA,
                                             sampleVisibilityThresholds: thresholds))]
        let c: [VectorElement] = []
        let recipe = recipe(motion: Self.still, a: a, c: c)

        let half = try XCTUnwrap(render(recipe, at: 0.5, a: a, c: c))
        XCTAssertGreaterThan(alpha(half, at: near), 0, "The early samples are visible at t = 0.5")
        XCTAssertEqual(alpha(half, at: far), 0, "The late ones are not")

        // Asserted on the evaluation rather than on pixels. The stroke exists at A and not at C, so
        // at `t = 1` it has cross-faded to nothing however many samples survived the gate — reading
        // the sample count separates "the thresholds released it" from "the fade took it away".
        let whole = try XCTUnwrap(InterpolationEvaluator.evaluate(recipe: recipe, at: 1,
                                                                  content: content(a: a, c: c)))
        XCTAssertEqual(whole.forward.first?.stroke?.samples.count, samples.count,
                       "By t = 1 every sample has passed its threshold")
    }

    // MARK: - Fills

    func testAFillIsWarpedByTheLattice() throws {
        let square = CGPath(rect: CGRect(x: 40, y: 40, width: 40, height: 40), transform: nil)
        var element = VectorFillElement(path: square,
                                        color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        element.id = ID.fill
        let a = [VectorElement.fill(element)]
        let c: [VectorElement] = []
        let recipe = recipe(motion: Self.translated(), a: a, c: c)

        XCTAssertGreaterThan(alpha(try XCTUnwrap(render(recipe, at: 0, a: a, c: c)),
                                   at: CGPoint(x: 60, y: 60)), 0,
                             "Setup: the fill starts here")

        // Read at 0.9 rather than 1. The fill exists at A and not at C, so by `t = 1` it has faded
        // out entirely — which is the endpoint invariant working, not the warp failing. At 0.9 it is
        // 36pt along and still at a tenth of its opacity, which is what this test is asking about.
        let late = try XCTUnwrap(render(recipe, at: 0.9, a: a, c: c))
        XCTAssertEqual(alpha(late, at: CGPoint(x: 60, y: 60)), 0,
                       "By t = 0.9 the fill has left its starting square")
        XCTAssertGreaterThan(alpha(late, at: CGPoint(x: 100, y: 60)), 0,
                             "…and travelled right with the lattice")
    }

    // MARK: - Well-formedness (§5.8)

    func testAnUnderspecifiedRecipeDoesNotEvaluate() {
        let single = InterpolationRecipe(references: [InterpolationReference(cels: [Self.celARef])])
        XCTAssertNil(InterpolationEvaluator.evaluate(recipe: single, at: 0.5, content: { _ in [] }),
                     "One reference is not an interpolation")

        let lattice = Lattice(cols: 2, rows: 2, restOrigin: .zero, restCellSize: 20)
        let mismatched = InterpolationRecipe(
            references: [InterpolationReference(cels: [Self.celARef]),
                         InterpolationReference(cels: [Self.celCRef])],
            groups: [MotionGroupBinding(groupID: ID.group, lattices: [lattice])])
        XCTAssertNil(InterpolationEvaluator.evaluate(recipe: mismatched, at: 0.5, content: { _ in [] }),
                     "A binding must carry one lattice per reference")
    }

    /// A recipe with no bindings is legal and means "warp the whole frame as one group" — with no
    /// lattices there is no motion to apply, so it degrades to a straight cross-fade rather than
    /// failing.
    func testARecipeWithNoGroupBindingsCrossFadesInPlace() throws {
        let a = [bar(y: 60, id: ID.paintA)]
        let c = [bar(y: 100, id: ID.paintC)]
        let bare = InterpolationRecipe(
            references: [InterpolationReference(cels: [Self.celARef]),
                         InterpolationReference(cels: [Self.celCRef])])

        let evaluation = try XCTUnwrap(InterpolationEvaluator.evaluate(
            recipe: bare, at: 0.25, content: content(a: a, c: c)))
        XCTAssertEqual(evaluation.forwardWeight, 0.75, accuracy: 1e-12)
        XCTAssertEqual(evaluation.backwardWeight, 0.25, accuracy: 1e-12)
        XCTAssertEqual(evaluation.forward.first?.stroke?.samples.map(\.point),
                       a.first?.stroke?.samples.map(\.point),
                       "Nothing to warp with, so nothing moves")
        XCTAssertEqual(evaluation.backward.first?.stroke?.samples.map(\.point),
                       c.first?.stroke?.samples.map(\.point))
    }

    // MARK: - Determinism

    func testEvaluatingTheSameRecipeTwiceProducesIdenticalBytes() throws {
        let a = [bar(y: 60, id: ID.paintA)]
        let c = [bar(y: 100, id: ID.paintC)]
        let recipe = recipe(motion: Self.translated(), a: a, c: c)

        let first = try XCTUnwrap(render(recipe, at: 0.37, a: a, c: c))
        let second = try XCTUnwrap(render(recipe, at: 0.37, a: a, c: c))
        let report = try XCTUnwrap(RasterVectorParity.report(raster: first, vector: second,
                                                            size: Self.canvasSize))
        XCTAssertTrue(report.isExact, "A scrub back to the same t must not shimmer: \(report.diagnostic)")
    }

    // MARK: - The preview tier (PLAN §8)

    /// Preview draws the same shapes in the same places — it drops dab texture, not geometry. The
    /// comparison is deliberately coarse: downsampled and loosely toleranced, because an exact match
    /// would mean preview was doing the expensive thing after all.
    func testPreviewIsVisuallyCloseToFull() throws {
        let elements = Self.manyStrokes()
        let full = flat(elements, quality: .full)
        let preview = flat(elements, quality: .preview)

        let coarse = CGSize(width: 20, height: 20)
        let report = try XCTUnwrap(RasterVectorParity.report(raster: Self.downsampled(full, to: coarse),
                                                            vector: Self.downsampled(preview, to: coarse),
                                                            size: coarse))
        XCTAssertLessThan(report.meanChannelDelta, 24,
                          "Preview should read as the same drawing: \(report.diagnostic)")
    }

    /// The claim that justifies the tier existing at all: preview does *categorically* less work than
    /// full, not just faster work. Originally this asserted `previewSeconds * 4 < fullSeconds`, timed
    /// on a simulator; measured 2026-08-17 across four isolated runs, that ratio came out 3.05x and
    /// 3.94x as often as it cleared 4x — machine contention decides a wall-clock comparison this close
    /// (~1.4-2.0ms vs ~5.7-6.2ms), which is exactly the ambiguity CLAUDE.md warns a red result can be
    /// evidence about the machine rather than the code.
    ///
    /// Asserting on `lastRenderDabCount` instead states the real invariant and is immune to
    /// contention: `.full` stamps one dab per `stampSpacing` interval via `BrushStamper`
    /// (`VectorCanvas.stamp`), while `.preview` strokes one `CGPath` per stroke and never touches
    /// `DabTarget` at all (`VectorCanvas.strokePolyline`) — see `draw(stroke:into:target:isEraser:
    /// quality:)`. So preview's dab count is always exactly zero and full's is in the thousands for
    /// `manyStrokes()`'s 24 strokes (24 strokes × ~136pt / 1pt spacing ≈ 3264); the `1000` floor below
    /// leaves wide headroom under that without hard-coding the exact figure.
    func testPreviewIsSubstantiallyCheaperThanFull() {
        let elements = Self.manyStrokes()

        let full = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = full.render(quality: .full)
        let preview = VectorCanvas(size: Self.canvasSize, elements: elements)
        _ = preview.render(quality: .preview)

        XCTAssertEqual(preview.lastRenderDabCount, 0,
                       "preview must never stamp a dab — that would make it full cost with extra steps")
        XCTAssertGreaterThan(full.lastRenderDabCount, 1000,
                             "sanity check that full is doing substantial per-dab work to be cheaper than")
    }

    /// The two caches are independent, which is what stops a slider release from throwing away the
    /// preview the next drag wants (and vice versa).
    func testPreviewAndFullAreCachedSeparatelyAndClearedTogether() {
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [bar(y: 80, id: ID.paintA)])
        XCTAssertFalse(canvas.hasCachedImage)
        _ = canvas.render(quality: .preview)
        XCTAssertTrue(canvas.hasCachedImage, "A preview render is memoized too")
        _ = canvas.render(quality: .full)

        canvas.dropCachedImage()
        XCTAssertFalse(canvas.hasCachedImage, "Dropping frees both qualities")
    }

    /// Isolation is a property of the walk, not of the stamp, so it must hold at preview fidelity as
    /// well. A preview that got this wrong would be worse than no preview.
    func testPreviewHonoursEraserIsolationToo() throws {
        let hole = CGPoint(x: 80, y: 80)
        let a = [bar(y: 80, id: ID.paintA),
                 bar(y: 80, from: 60, to: 100, id: ID.eraser, size: 30, composite: .erase)]
        let c = [bar(y: 80, id: ID.paintC)]
        let recipe = recipe(motion: Self.still, a: a, c: c)

        let preview = try XCTUnwrap(render(recipe, at: 0.5, a: a, c: c, quality: .preview))
        XCTAssertGreaterThan(alpha(preview, at: hole), 0,
                             "C's stroke must survive A's eraser at preview fidelity as well")
    }

    // MARK: - Support

    /// Enough strokes that the two tiers' costs are separable on a simulator.
    private static func manyStrokes() -> [VectorElement] {
        (0..<24).map { index in
            let y = 10 + CGFloat(index) * 6
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000%05d", index))!
            return .stroke(VectorStroke(id: id, brush: brush,
                                        color: CodableColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
                                        size: 5, opacity: 1,
                                        samples: [VectorSample(x: 12, y: y, pressure: 1),
                                                  VectorSample(x: 148, y: y, pressure: 1)]))
        }
    }

    private static func downsampled(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = PixelOps.transparentFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
