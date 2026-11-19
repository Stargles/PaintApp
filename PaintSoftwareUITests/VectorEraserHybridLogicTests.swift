import XCTest
import UIKit
import CoreGraphics

/// `VectorCanvas.eraseHybrid` — the Mode 1 commit — under test.
///
/// `RasterVectorParityLogicTests` proves the two *representations* agree: a hand-built display list
/// ending in an `.erase` element renders exactly what a raster layer erased the same way renders.
/// That is a claim about the renderer. It says nothing about whether the code that actually decides
/// what to delete and what to retain produces such a display list, and until this file existed nothing
/// executed `eraseHybrid` at all.
///
/// So this asserts the four things the hybrid claims, in the order they matter:
///
/// 1. **Exactness.** Running a real erase through `VectorCanvas.erase(…, mode: .erase)` and rendering
///    the result is byte-identical to the raster ground truth, over the same brush/opacity/gesture
///    matrix as the parity tests, at tolerance zero. This is the design's whole justification and
///    the one test that can falsify it.
/// 2. **Whole-stroke deletion** fires where the eraser covers a stroke completely, and nowhere else.
/// 3. **The partial split**, which ships now that `DabLattice` lets a piece render on its parent's
///    dabs — together with the measurement that says a split *without* that still diverges, so the
///    reason the lattice exists is pinned rather than remembered.
/// 4. **The list does not grow.** A fully resolved erase retains nothing, and GC drops a punch whose
///    backdrop is gone.
///
/// Same arrangement as the other logic tests: the engine files are compiled into this target as well
/// as the app, so no `@testable import`. Nothing here drives a simulator.
final class VectorEraserHybridLogicTests: XCTestCase {

    // MARK: - The scene
    //
    // Deliberately the same geometry as the parity matrix — a 24pt line across a 128² canvas, erased
    // by a 16pt nib — so a failure here can be read against a green assertion there rather than
    // against a differently-shaped scene. Tests about whole-stroke coverage need a wider nib and say
    // so; see `wideNib`.

    private static let canvasSize = CGSize(width: 128, height: 128)
    private static let paintID = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
    /// The field `RasterVectorParity.paintStroke` gives the paint stroke — the thing a piece must
    /// inherit now that BRUSH.md §4 took the seed off the id.
    private static let paintSeed = DabRandom.seed(for: paintID)
    private static let eraserID = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!

    private static func ramp(from start: CGPoint, to end: CGPoint, count: Int,
                             from p0: CGFloat, to p1: CGFloat) -> StrokeSamples {
        StrokeSamples((0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            return VectorSample(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t,
                                pressure: p0 + (p1 - p0) * t)
        }, channels: .pressureOnly)
    }

    /// The line under the eraser: ink spans y ∈ [52, 76] at full pressure.
    private static let paintSamples: StrokeSamples = ramp(from: CGPoint(x: 24, y: 64), to: CGPoint(x: 104, y: 64),
                                           count: 9, from: 0.45, to: 1)

    private enum Gesture: String, CaseIterable {
        /// Straight across the line.
        case squareCut
        /// Across at 45°, so both cut boundaries land between samples.
        case diagonalCut
        /// Along the line, shaving its top edge — partial-width coverage, which only a punch can express.
        case edgeShave

        var samples: StrokeSamples {
            switch self {
            case .squareCut:
                return ramp(from: CGPoint(x: 64, y: 24), to: CGPoint(x: 64, y: 104), count: 9, from: 1, to: 1)
            case .diagonalCut:
                return ramp(from: CGPoint(x: 36, y: 36), to: CGPoint(x: 92, y: 92), count: 9, from: 1, to: 1)
            case .edgeShave:
                return ramp(from: CGPoint(x: 28, y: 54), to: CGPoint(x: 100, y: 54), count: 9, from: 1, to: 1)
            }
        }

        var label: String {
            switch self {
            case .squareCut: return "square cut"
            case .diagonalCut: return "diagonal cut"
            case .edgeShave: return "partial-width shave"
            }
        }
    }

    private func scenario(brush: Brush, eraserBrush: Brush? = nil, eraserOpacity: Double = 1,
                          eraserSize: CGFloat = 16, gesture: Gesture = .squareCut,
                          eraserSamples: StrokeSamples? = nil,
                          backdrop: ParityScenario.Backdrop = .none,
                          name: String = "") -> ParityScenario {
        ParityScenario(name: name,
                       canvasSize: Self.canvasSize,
                       brush: brush,
                       paintColor: CodableColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1),
                       paintSize: 24,
                       paintOpacity: 1,
                       paintSamples: Self.paintSamples,
                       eraserBrush: eraserBrush ?? brush,
                       eraserColor: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                       eraserSize: eraserSize,
                       eraserOpacity: eraserOpacity,
                       eraserSamples: eraserSamples ?? gesture.samples,
                       backdrop: backdrop,
                       paintID: Self.paintID,
                       eraserID: Self.eraserID)
    }

    // MARK: - Driving the real commit

    /// The scenario's paint stroke on a real `VectorCanvas`, erased through the real Mode 1 entry
    /// point. Returns the canvas *and* the backdrop element it was built from, because the raster
    /// ground truth has to be seeded from the very same element — a placed image rendered twice is
    /// two different `UIImage`s, and comparing them would fold "does this render deterministically"
    /// into a number that is supposed to be about the eraser.
    @discardableResult
    private func erased(_ scenario: ParityScenario) throws -> (canvas: VectorCanvas, backdrop: VectorElement?,
                                                        changed: Bool) {
        let backdrop = try RasterVectorParity.backdropElement(scenario)
        let elements = (backdrop.map { [$0] } ?? []) + [.stroke(RasterVectorParity.paintStroke(scenario))]
        let canvas = VectorCanvas(size: scenario.canvasSize, elements: elements)
        let changed = canvas.erase(alongPath: scenario.eraserSamples, brush: scenario.eraserBrush,
                                   size: scenario.eraserSize, opacity: scenario.eraserOpacity,
                                   mode: .erase, seed: DabRandom.seed(for: scenario.eraserID))
        return (canvas, backdrop, changed)
    }

    /// The hybrid's render against the raster ground truth for the same scene.
    ///
    /// The ground truth matches the parity tests: stamp the paint stroke whole, then stamp the eraser
    /// gesture whole with `isEraser: true`. The vector side is whatever `eraseHybrid` decided to
    /// leave in the display list — the stroke plus a punch, a punch alone, or nothing at all.
    ///
    /// Both actual commits receive the scenario's field, independently of each element's identity.
    private func parityOfHybrid(_ scenario: ParityScenario) throws -> ParityReport? {
        let (canvas, backdrop, _) = try erased(scenario)
        let texture = try RasterVectorParity.rasterBase(scenario, backdrop: backdrop)
        RasterVectorParity.stamp(RasterVectorParity.paintStroke(scenario), into: texture, isEraser: false)
        RasterVectorParity.stamp(RasterVectorParity.eraseStroke(scenario), into: texture, isEraser: true)
        return RasterVectorParity.report(raster: try texture.renderToUIImage().get(), vector: (try XCTUnwrap(canvas.render())),
                                         size: scenario.canvasSize)
    }

    private func strokes(_ canvas: VectorCanvas, _ composite: StrokeComposite) -> [VectorStroke] {
        canvas.elements.compactMap(\.stroke).filter { $0.composite == composite }
    }

    // MARK: - 1. Exactness — the claim the whole design rests on

    private static let brushes = [TestBrushes.hardRound, TestBrushes.softRound]
    private static let eraserOpacities: [Double] = [1, 0.4]

    private func assertHybridMatchesRaster(over backdropName: String, _ backdrop: ParityScenario.Backdrop,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        for brush in Self.brushes {
            for eraserOpacity in Self.eraserOpacities {
                for gesture in Gesture.allCases {
                    let name = "\(brush.name) / eraser opacity \(eraserOpacity) / \(gesture.label) / \(backdropName)"
                    let scene = scenario(brush: brush, eraserOpacity: eraserOpacity,
                                         gesture: gesture, backdrop: backdrop, name: name)
                    try XCTContext.runActivity(named: name) { _ in
                        guard let report = try parityOfHybrid(scene) else {
                            return XCTFail("Could not read back both tiers for \(name)", file: file, line: line)
                        }
                        XCTAssertTrue(report.isExact,
                                      "\(name) — the hybrid commit is not pixel-identical to raster erasing: \(report.diagnostic)",
                                      file: file, line: line)
                    }
                }
            }
        }
    }

    func testHybridEraseOverABareStrokeIsPixelIdenticalToRasterErasing() throws {
        try assertHybridMatchesRaster(over: "bare stroke", .none)
    }

    func testHybridEraseOverAVectorFillIsPixelIdenticalToRasterErasing() throws {
        try assertHybridMatchesRaster(over: "over a fill",
                                  .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                        CGRect(x: 8, y: 40, width: 112, height: 48)))
    }

    func testHybridEraseOverAPlacedImageIsPixelIdenticalToRasterErasing() throws {
        try assertHybridMatchesRaster(over: "over a placed image",
                                  .image(UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1),
                                         CGSize(width: 64, height: 64)))
    }

    /// The matrix above compares two renders and passes when they agree, so it would also pass if
    /// `erase` had done nothing and the raster tier's eraser had missed. Both are pinned here.
    func testTheMatrixIsNotVacuous() throws {
        for gesture in Gesture.allCases {
            let scene = scenario(brush: TestBrushes.hardRound, gesture: gesture)
            let (canvas, _, changed) = try erased(scene)
            XCTAssertTrue(changed, "\(gesture.label) should report a change")

            let before = (try XCTUnwrap(VectorCanvas(size: scene.canvasSize,
                                      elements: [.stroke(RasterVectorParity.paintStroke(scene))]).render()))
            guard let report = RasterVectorParity.report(raster: before, vector: (try XCTUnwrap(canvas.render())),
                                                         size: scene.canvasSize) else {
                return XCTFail("Could not read back the before/after renders for \(gesture.label)")
            }
            XCTAssertGreaterThan(report.differingPixelCount, 200,
                                 "\(gesture.label) barely changed the render: \(report.diagnostic)")
            XCTAssertGreaterThan(report.maxChannelDelta, 128,
                                 "\(gesture.label) should remove ink outright somewhere: \(report.diagnostic)")
        }
    }

    // MARK: - 2. Whole-stroke deletion

    /// A nib comfortably wider than the 24pt line, so a crossing covers a genuine span of it rather
    /// than grazing. The parity matrix deliberately uses 16 — the awkward size — so tests about
    /// coverage need their own.
    private static let wideNib: CGFloat = 48

    /// The one geometric verdict Mode 1 acts on: a gesture that covers a stroke end to end deletes it.
    /// Nothing is re-stamped, so this cannot move a pixel — and the punch that remains has a fill
    /// beneath it here, so there is still something to check against raster.
    func testAGestureCoveringAStrokeEndToEndDeletesIt() throws {
        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: along,
                             backdrop: .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                             CGRect(x: 8, y: 40, width: 112, height: 48)))
        let (canvas, _, changed) = try erased(scene)
        XCTAssertTrue(changed)
        XCTAssertEqual(strokes(canvas, .paint).count, 0, "The covered stroke should be gone outright")
        XCTAssertEqual(strokes(canvas, .erase).count, 1,
                       "The fill beneath still needs the punch, or the hole in it reappears")
        guard let report = try parityOfHybrid(scene) else { return XCTFail("Could not read back both tiers") }
        XCTAssertTrue(report.isExact, "Deleting a covered stroke must not move a pixel: \(report.diagnostic)")
    }

    /// Partial coverage never *deletes*, however inviting it looks — deletion needs the eraser to cover
    /// the stroke end to end, caps included.
    ///
    /// What partial coverage does now depends on which kind of partial it is, and the two are worth
    /// keeping in one test because they were one case until `DabLattice` existed:
    ///
    /// - Covered **full width** over a stretch, and only there: the stroke is *cut*, into pieces that
    ///   render on the parent's lattice. `testTheSplitIsExactOnlyBecauseThePiecesShareTheParentsLattice`
    ///   is why that split is allowed to happen.
    /// - Never covered full width anywhere — a shave along one edge, a nib narrower than the line —
    ///   there is nothing to cut and the punch is the whole answer, so the stroke stays whole and keeps
    ///   its id.
    ///
    /// Every row still has to be pixel-exact against raster, which is the only thing that makes the
    /// difference between the two an implementation detail rather than a visible one.
    func testPartialCoverageSplitsOrPunchesButNeverDeletes() throws {
        // Squarely across the middle: the classic "cut in two" gesture, which is exactly the one Mode 1
        // no longer acts on. See `VectorEraser`'s Mode 1 notes.
        let across = Gesture.squareCut.samples
        // Along the line but high, so a radius-24 nib reaches y = 60 — past the top edge at 52, short
        // of the bottom at 76.
        let shave = Self.ramp(from: CGPoint(x: 20, y: 36), to: CGPoint(x: 108, y: 36), count: 9,
                              from: 1, to: 1)
        // End to end along the line, but too narrow to cover its width anywhere.
        let thin = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                             from: 1, to: 1)

        let cases: [(name: String, pieces: Int, scene: ParityScenario)] = [
            ("a square crossing", 2, scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib,
                                              eraserSamples: across)),
            ("a partial-width shave", 1, scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib,
                                                  eraserSamples: shave)),
            ("a nib narrower than the line", 1, scenario(brush: TestBrushes.hardRound, eraserSize: 6,
                                                         eraserSamples: thin))
        ]

        for (name, expectedPieces, scene) in cases {
            try XCTContext.runActivity(named: name) { _ in
                let (canvas, _, _) = try erased(scene)
                let paint = strokes(canvas, .paint)
                XCTAssertEqual(paint.count, expectedPieces,
                               "\(name) should leave \(expectedPieces) piece(s) — and never zero, which would be deletion")
                if expectedPieces == 1 {
                    XCTAssertEqual(paint.first?.id, Self.paintID,
                                   "\(name) changed nothing about the stroke, so it must keep its id and dab seed")
                    XCTAssertNil(paint.first?.lattice,
                                 "\(name) never cut the stroke, so it is still its own lattice")
                } else {
                    for piece in paint {
                        XCTAssertNotEqual(piece.id, Self.paintID, "\(name): a piece is a new stroke")
                        XCTAssertEqual(piece.seed, Self.paintSeed,
                                       "\(name): a piece must inherit the parent's random field")
                        XCTAssertEqual(piece.lattice?.samples.count, Self.paintSamples.count,
                                       "\(name): a piece must carry the parent's whole walk, not its own samples")
                        XCTAssertLessThan(piece.samples.count, Self.paintSamples.count,
                                          "\(name): a piece's own geometry is shorter than the parent's")
                    }
                }
                XCTAssertEqual(strokes(canvas, .erase).count, 1,
                               "\(name) still has to retain a punch, or the ink is simply not erased")
                guard let report = try parityOfHybrid(scene) else {
                    return XCTFail("Could not read back both tiers for \(name)")
                }
                XCTAssertTrue(report.isExact, "\(name): \(report.diagnostic)")
            }
        }
    }

    /// `supportsCleanCut` gates deletion on the eraser being capable of removing ink outright. Each row
    /// is a distinct condition, run over the gesture that *would* delete, so a regression that drops one
    /// condition fails on that row alone.
    func testDeletionIsSkippedWhereverTheAlphaGateFails() throws {
        var scattering = TestBrushes.hardRound
        scattering.dab.scatterAcross = 0.4
        scattering.dab.scatterAlong = 0.4
        var jittering = TestBrushes.hardRound
        jittering.dab.angle.jitter = 0.5
        var square = TestBrushes.hardRound
        square.tip = .stamp(.builtIn(.square))
        var soft = TestBrushes.hardRound
        soft.dab.hardness = 0.5

        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        func rejected(_ eraserBrush: Brush? = nil, opacity: Double = 1) -> ParityScenario {
            scenario(brush: TestBrushes.hardRound, eraserBrush: eraserBrush, eraserOpacity: opacity,
                     eraserSize: Self.wideNib, eraserSamples: along)
        }
        let cases: [(String, ParityScenario)] = [
            ("soft falloff", rejected(TestBrushes.softRound)),
            ("hardness below the gate", rejected(soft)),
            ("partial opacity", rejected(opacity: 0.4)),
            ("scattering eraser", rejected(scattering)),
            ("rotation-jittering square eraser", rejected(jittering)),
            ("square eraser", rejected(square))
        ]

        for (name, scene) in cases {
            try XCTContext.runActivity(named: name) { _ in
                let (canvas, _, _) = try erased(scene)
                XCTAssertEqual(strokes(canvas, .paint).count, 1,
                               "\(name) must not delete the stroke — the gate rejected this eraser")
                XCTAssertEqual(strokes(canvas, .paint).first?.id, Self.paintID)
                XCTAssertEqual(strokes(canvas, .erase).count, 1)
            }
        }
    }

    /// **BRUSH.md §9's one behaviour change: the grain veto is gone, and the Pencil preset is no
    /// longer special-cased out of `supportsCleanCut`.**
    ///
    /// Before BRUSH.md §12 stage 2, `supportsCleanCut` carried an extra `guard !brush.grain.isEnabled`
    /// beside the hardness/opacity/dynamics/scatter gates above — and the shipped `TestBrushes.pencil`
    /// preset had grain enabled, so a pencil-*shaped* eraser could never take the clean-cut path no
    /// matter how hard, opaque or steady it was tuned. There is no `grain` field left to check, so that
    /// extra veto is simply gone: the Pencil preset is judged on exactly the same four gates as Soft
    /// Round, Hard Round and Pen, with nothing held against it. Since §12 stage 5 all four are one
    /// `BrushTip.round` and there is not even a shape left to hold against it.
    ///
    /// `TestBrushes.pencil`'s own hardness (0.7) still fails the unrelated hardness gate on its own, so
    /// this pins the shape in isolation against a brush tuned to clear every *other* gate — the only way
    /// to isolate what the grain veto used to cost it, now that grain cannot be toggled to show the
    /// same brush passing and failing.
    func testAHardOpaquePencilShapedEraserCleanCutsWhereGrainUsedToVetoIt() throws {
        var pencilEraser = TestBrushes.pencil
        pencilEraser.dab.hardness = 1
        // **The setup assertion used to be `BrushLibrary.isPencilPreset`, and it had to go at §12
        // stage 9** — not because the subject moved but because that predicate did. It named one
        // preset id when this was written; it is now membership of §8.6's Sketching group, which is
        // a fact about the *picker* and says nothing whatever about a brush's ink. Asserting it here
        // would have been true of the library rather than of the eraser under test. What the gates
        // actually read is below, and it is what the grain veto used to override.
        guard case .round = pencilEraser.tip else {
            return XCTFail("Setup: a pencil-shaped eraser is a round nib — the four gates read the "
                           + "tip, the hardness, the flow and the opacity, and nothing else")
        }

        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: TestBrushes.hardRound, eraserBrush: pencilEraser, eraserSize: Self.wideNib,
                             eraserSamples: along,
                             backdrop: .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                             CGRect(x: 8, y: 40, width: 112, height: 48)))
        let (canvas, _, changed) = try erased(scene)
        XCTAssertTrue(changed)
        XCTAssertEqual(strokes(canvas, .paint).count, 0,
                       "A hard, opaque, steady pencil-shaped eraser now deletes what it fully covers")
        XCTAssertEqual(strokes(canvas, .erase).count, 1,
                       "The fill beneath still needs the punch, or the hole in it reappears")
        guard let report = try parityOfHybrid(scene) else { return XCTFail("Could not read back both tiers") }
        XCTAssertTrue(report.isExact, "Deleting a covered stroke must not move a pixel: \(report.diagnostic)")
    }

    /// The other half of the gate. A *paint* stroke that scatters throws dabs off its own centreline,
    /// so the capsule chain the coverage test measures against does not bound its ink and "covered" is
    /// a claim about the wrong shape. Such a stroke is never deleted, only punched.
    func testAScatteringPaintStrokeIsNeverDeleted() throws {
        var scattering = TestBrushes.hardRound
        scattering.dab.scatterAcross = 0.5
        scattering.dab.scatterAlong = 0.5
        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: scattering, eraserBrush: TestBrushes.hardRound,
                             eraserSize: Self.wideNib, eraserSamples: along)
        let (canvas, _, _) = try erased(scene)
        XCTAssertEqual(strokes(canvas, .paint).count, 1,
                       "A scattering stroke must be erased by the punch alone")
        XCTAssertEqual(strokes(canvas, .paint).first?.id, Self.paintID)
    }

    // MARK: - 3. The partial split, and the one thing that makes it exact

    /// The split works because the pieces keep the parent's dab lattice, and this measures both halves
    /// of that sentence in one scene.
    ///
    /// Cut the stroke at the span `conservativeCuts` says is safe — a hard round eraser at full opacity
    /// crossing squarely — then render the pieces plus the punch twice: once with the pieces re-stamped
    /// as fresh strokes, the way every split did before `DabLattice`, and once with the pieces sharing
    /// the parent's walk. Compare each against the whole stroke plus the same punch.
    ///
    /// The naive pieces **diverge**, and outside the punch: a fresh stroke re-anchors `BrushStamper`'s
    /// lattice at its own first sample, so its ink lands somewhere new along its entire length — most
    /// visibly at the far tip, the end furthest from the eraser and therefore the one the punch cannot
    /// cover.
    ///
    /// The lattice-sharing pieces are **exact**, because their dabs are not a reconstruction of the
    /// parent's; `stampStroke` makes the identical calls and drops the ones outside the range.
    ///
    /// If the first assertion ever starts passing — i.e. a naive split becomes exact by itself — the
    /// stamper's anchoring has changed and `DabLattice` may no longer be earning its keep. If the
    /// second fails, the split is putting ink outside the gesture and must come back out of
    /// `eraseHybrid`.
    func testTheSplitIsExactOnlyBecauseThePiecesShareTheParentsLattice() throws {
        let scene = scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib)
        let paint = RasterVectorParity.paintStroke(scene)
        let erase = RasterVectorParity.eraseStroke(scene)
        guard let sweep = VectorEraser.Sweep(samples: erase.samples, brush: erase.brush,
                                             size: erase.size) else {
            return XCTFail("The eraser gesture should have a footprint")
        }
        let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: erase.brush, size: erase.size)
        let clean = VectorEraser.cleanCutRanges(in: paint.samples, brush: paint.brush, size: paint.size,
                                                by: erasers, sweep: sweep)
        XCTAssertEqual(clean.count, 1,
                       "A square crossing covers one contiguous span — if this fragments, the merge in cleanCutRanges regressed")
        let cuts = VectorEraser.conservativeCuts(clean, in: paint.samples, brush: paint.brush,
                                                 size: paint.size, by: erasers)
        XCTAssertFalse(cuts.isEmpty,
                       "The inset must leave something to cut here, or this test is not measuring the split")

        let runs = StrokeGeometry.splitStrokeRuns(paint.samples, removing: cuts)
        XCTAssertEqual(runs.count, 2, "A square crossing should yield two pieces")

        // (a) The old way: each piece is a stroke unto itself, re-stamped from its own first sample.
        let naive: [VectorElement] = runs.map { run in
            var piece = paint
            piece.id = UUID()
            piece.samples = paint.samples.replacingSamples(run.samples)
            return .stroke(piece)
        }
        // (b) The shipped way: same geometry, but the dabs come from the parent's walk.
        let shared: [VectorElement] = runs.map { run in
            var piece = paint
            piece.id = UUID()
            piece.samples = paint.samples.replacingSamples(run.samples)
            piece.lattice = DabLattice(samples: paint.samples, parameters: run.parameters)
            return .stroke(piece)
        }

        let whole = (try XCTUnwrap(VectorCanvas(size: scene.canvasSize,
                                 elements: [.stroke(paint), .stroke(erase)]).render()))
        guard let naiveReport = RasterVectorParity.report(
                raster: whole,
                vector: (try XCTUnwrap(VectorCanvas(size: scene.canvasSize, elements: naive + [.stroke(erase)]).render())),
                size: scene.canvasSize),
              let sharedReport = RasterVectorParity.report(
                raster: whole,
                vector: (try XCTUnwrap(VectorCanvas(size: scene.canvasSize, elements: shared + [.stroke(erase)]).render())),
                size: scene.canvasSize) else {
            return XCTFail("Could not read back the renders")
        }
        XCTAssertFalse(naiveReport.isExact,
                       "Re-stamping the pieces as fresh strokes is supposed to move ink — if it no longer does, the stamper's lattice anchoring has changed and DabLattice needs re-justifying. Measured: \(naiveReport.diagnostic)")
        XCTAssertTrue(sharedReport.isExact,
                      "Pieces sharing the parent's lattice must be pixel-identical to the uncut stroke under the same punch: \(sharedReport.diagnostic)")
    }

    /// The pieces the *real commit* produces, cut again by a second gesture.
    ///
    /// A piece's cut parameters are in its own domain, not the parent's, so composing a second split
    /// onto the first is the one place the mapping in `DabLattice.parentParameter(of:)` is exercised.
    /// Get it wrong and the grandchild shows the wrong stretch of the parent's dabs — which looks like
    /// ink jumping on the second erase, not on the first.
    func testCuttingAPieceAgainStaysOnTheOriginalLattice() throws {
        // First gesture: squarely across the middle at x = 64, which splits the line in two.
        let first = Self.ramp(from: CGPoint(x: 64, y: 24), to: CGPoint(x: 64, y: 104), count: 9,
                              from: 1, to: 1)
        // Second: across the left-hand piece at x = 40.
        let second = Self.ramp(from: CGPoint(x: 40, y: 24), to: CGPoint(x: 40, y: 104), count: 9,
                               from: 1, to: 1)
        let scene = scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: first)
        let paint = RasterVectorParity.paintStroke(scene)
        let canvas = VectorCanvas(size: scene.canvasSize, elements: [.stroke(paint)])
        canvas.erase(alongPath: first, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))
        XCTAssertEqual(strokes(canvas, .paint).count, 2, "The first gesture should have split the line")
        canvas.erase(alongPath: second, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))

        let pieces = strokes(canvas, .paint)
        XCTAssertGreaterThanOrEqual(pieces.count, 2, "The second gesture should have cut again")
        for piece in pieces {
            XCTAssertEqual(piece.seed, Self.paintSeed,
                           "A grandchild still draws from the original stroke's random field")
            XCTAssertEqual(piece.lattice?.samples.count, Self.paintSamples.count,
                           "…and points at the original's samples, not its parent piece's")
            guard let range = piece.lattice?.range else {
                return XCTFail("A piece must have a readable range")
            }
            XCTAssertTrue(range.lowerBound >= 0 && range.upperBound <= CGFloat(Self.paintSamples.count - 1),
                          "A grandchild's range must live in the original's domain, not a piece's: \(range)")
        }

        // The whole point: two erases in, the surviving ink is still the original's dabs, so the result
        // matches raster erasing the same line with the same two gestures.
        let texture = try RasterVectorParity.rasterBase(scene, backdrop: nil)
        RasterVectorParity.stamp(paint, into: texture, isEraser: false)
        for gesture in [first, second] {
            var punch = RasterVectorParity.eraseStroke(scene)
            punch.samples = gesture
            RasterVectorParity.stamp(punch, into: texture, isEraser: true)
        }
        guard let report = RasterVectorParity.report(raster: try texture.renderToUIImage().get(),
                                                     vector: (try XCTUnwrap(canvas.render())),
                                                     size: scene.canvasSize) else {
            return XCTFail("Could not read back both tiers")
        }
        XCTAssertTrue(report.isExact, "Two erases must still be raster-exact: \(report.diagnostic)")
    }

    /// Deletion, by contrast, *is* exact — the property that lets Mode 1 keep it. Same shape of
    /// comparison as above, with the whole stroke removed instead of cut.
    func testDeletingAFullyCoveredStrokeIsExact() throws {
        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: along)
        let paint = RasterVectorParity.paintStroke(scene)
        let erase = RasterVectorParity.eraseStroke(scene)
        guard let sweep = VectorEraser.Sweep(samples: erase.samples, brush: erase.brush,
                                             size: erase.size) else {
            return XCTFail("The eraser gesture should have a footprint")
        }
        let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: erase.brush, size: erase.size)
        XCTAssertTrue(VectorEraser.isEntirelyCovered(paint.samples, brush: paint.brush, size: paint.size,
                                                     by: erasers, sweep: sweep),
                      "This gesture is supposed to cover the stroke completely")

        guard let report = RasterVectorParity.report(
            raster: (try XCTUnwrap(VectorCanvas(size: scene.canvasSize,
                                 elements: [.stroke(paint), .stroke(erase)]).render())),
            vector: (try XCTUnwrap(VectorCanvas(size: scene.canvasSize, elements: [.stroke(erase)]).render())),
            size: scene.canvasSize) else {
            return XCTFail("Could not read back the two renders")
        }
        XCTAssertTrue(report.isExact,
                      "Removing a stroke the eraser wholly covers must change nothing: \(report.diagnostic)")
    }

    /// `isEntirelyCovered` must not be satisfied by cross-sections alone: a stroke whose body is under
    /// the eraser but whose end cap sticks out past it is not covered. The cap is the half-disc beyond
    /// the last parameter, which no cross-section test can see.
    func testAStrokeWhoseEndCapEscapesIsNotEntirelyCovered() {
        let scene = scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib)
        let paint = RasterVectorParity.paintStroke(scene)
        // Stops at x = 88. The nib's own radius-24 cap still reaches x = 112, so every *cross-section*
        // of the stroke (whose samples end at x = 104) is covered — but the stroke's ink runs to
        // x = 116 in its end cap, and that is outside. Isolating the cap check from the cross-section
        // check is the whole point: stopping any nearer and the nib swallows the cap too, which is what
        // this test originally did and why it did not test anything.
        let short = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 88, y: 64), count: 13,
                              from: 1, to: 1)
        guard let sweep = VectorEraser.Sweep(samples: short, brush: TestBrushes.hardRound,
                                             size: Self.wideNib) else {
            return XCTFail("The eraser gesture should have a footprint")
        }
        let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: TestBrushes.hardRound,
                                                    size: Self.wideNib)
        XCTAssertFalse(VectorEraser.isEntirelyCovered(paint.samples, brush: paint.brush, size: paint.size,
                                                      by: erasers, sweep: sweep),
                       "The trailing cap is outside the eraser, so the stroke is not entirely covered")

        let canvas = VectorCanvas(size: scene.canvasSize, elements: [.stroke(paint)])
        canvas.erase(alongPath: short, brush: TestBrushes.hardRound, size: Self.wideNib,
                     opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))
        XCTAssertEqual(strokes(canvas, .paint).count, 1, "…so it must survive")
    }

    // MARK: - 4. The display list does not grow

    /// The retain decision is a bit, and the punch it retains carries the gesture **whole**.
    ///
    /// Trimming the punch to the stretches with a backdrop is the obvious optimisation and it is
    /// wrong: `BrushStamper` starts its dab lattice at `samples[0]`, so a run that begins anywhere
    /// else moves every dab after it, including those over the ink. This pins the samples through, and
    /// pins that one gesture crossing two well-separated strokes yields **one** element rather than
    /// one per stretch — the version that trimmed produced two here.
    func testTheRetainedPunchKeepsTheWholeGesture() {
        // A 120pt vertical drag crossing the line at y = 64 and a second line at y = 112, with a long
        // stretch of empty canvas above the first and between the two.
        let drag = Self.ramp(from: CGPoint(x: 64, y: 4), to: CGPoint(x: 64, y: 124), count: 13,
                             from: 1, to: 1)
        let scene = scenario(brush: TestBrushes.hardRound, eraserSamples: drag)
        var second = RasterVectorParity.paintStroke(scene)
        second.id = UUID()
        second.samples = Self.ramp(from: CGPoint(x: 24, y: 112), to: CGPoint(x: 104, y: 112),
                                   count: 9, from: 1, to: 1)

        let canvas = VectorCanvas(size: scene.canvasSize,
                                  elements: [.stroke(RasterVectorParity.paintStroke(scene)),
                                             .stroke(second)])
        canvas.erase(alongPath: drag, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))

        let punches = strokes(canvas, .erase)
        XCTAssertEqual(punches.count, 1,
                       "Two separated backdrops along one gesture must still retain exactly one punch")
        XCTAssertEqual(punches.first?.samples.count, drag.count,
                       "The punch must carry the gesture whole, or its dab lattice re-phases")
        for (retained, original) in zip(punches.first?.samples ?? [], drag) {
            XCTAssertEqual(retained.x, original.x, accuracy: 1e-9)
            XCTAssertEqual(retained.y, original.y, accuracy: 1e-9)
            XCTAssertEqual(retained.pressure, original.pressure, accuracy: 1e-9)
        }
    }

    /// The common case that should cost nothing: scribble a stroke out completely and the layer ends
    /// up empty — the stroke deleted outright, and no punch left hanging over nothing.
    func testErasingAStrokeAwayCompletelyLeavesAnEmptyDisplayList() throws {
        let scene = scenario(brush: TestBrushes.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: Self.ramp(from: CGPoint(x: 8, y: 64),
                                                      to: CGPoint(x: 120, y: 64),
                                                      count: 15, from: 1, to: 1))
        let (canvas, _, changed) = try erased(scene)
        XCTAssertTrue(changed)
        XCTAssertEqual(canvas.elements.count, 0,
                       "A fully resolved erase must retain nothing at all, or Mode 1 grows the list forever")

        // And the layer really is blank, not merely element-free by accident.
        guard let bytes = RasterVectorParity.premultipliedBytes(of: (try XCTUnwrap(canvas.render())), size: scene.canvasSize) else {
            return XCTFail("Could not read back the render")
        }
        XCTAssertFalse(bytes.contains { $0 != 0 }, "The rendered layer should be fully transparent")
    }

    /// GC's second case: a punch whose backdrop is deleted later. It survives until the next erase —
    /// documented behaviour, since it renders as a hole in nothing — and is collected then.
    func testAPunchIsCollectedOnceItsBackdropIsDeleted() {
        let scene = scenario(brush: TestBrushes.hardRound)
        let target = RasterVectorParity.paintStroke(scene)
        // Down the left edge, clear of the first gesture's column (x = 64) even after GC pads the
        // punch's box by both half-widths — otherwise the bystander alone would keep it alive and the
        // test would be measuring the padding rather than the collection.
        var bystander = target
        bystander.id = UUID()
        bystander.samples = Self.ramp(from: CGPoint(x: 8, y: 24), to: CGPoint(x: 8, y: 112),
                                      count: 9, from: 1, to: 1)

        let canvas = VectorCanvas(size: scene.canvasSize,
                                  elements: [.stroke(target), .stroke(bystander)])
        canvas.erase(alongPath: scene.eraserSamples, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))
        XCTAssertEqual(strokes(canvas, .erase).count, 1, "The first erase should retain a punch")

        // Delete everything the punch was over, leaving it stranded.
        canvas.elements = canvas.elements.filter { $0.stroke?.composite == .erase || $0.stroke?.id == bystander.id }
        canvas.bumpVersion()
        XCTAssertEqual(strokes(canvas, .erase).count, 1, "GC runs on commit, not per frame")

        // Any later erase collects it — here, one over the bystander down the left edge.
        canvas.erase(alongPath: Self.ramp(from: CGPoint(x: 8, y: 96), to: CGPoint(x: 8, y: 124),
                                          count: 5, from: 1, to: 1),
                     brush: scene.eraserBrush, size: scene.eraserSize, opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))
        let remaining = strokes(canvas, .erase)
        XCTAssertEqual(remaining.count, 1,
                       "The stranded punch should be collected, leaving only the punch the second erase made")
        guard let box = remaining.first.flatMap({ StrokeGeometry.bounds(of: $0.samples) }) else {
            return XCTFail("The surviving punch should have bounds")
        }
        XCTAssertLessThan(box.maxX, 44,
                          "The survivor should be the second punch down the left edge — not the stranded one at x = 64")
    }

    // MARK: - Edges the implementation reaches for but nothing else exercises

    /// `erase` early-returns for Modes 2 and 3 on a layer with no strokes, but Mode 1 must not: a
    /// punch over a bare fill is its whole job. This is the guard in `erase`'s `mode == .erase ||` and
    /// the `maxPaintReach() == 0` path in `inkTouched`, which is correct only because the fill
    /// check runs before it.
    func testModeOneErasesAFillOnALayerWithNoStrokesAtAll() throws {
        let rect = CGRect(x: 8, y: 40, width: 112, height: 48)
        let fill = VectorFillElement(path: CGPath(rect: rect, transform: nil),
                                     color: CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill)])
        let gesture = Gesture.squareCut.samples
        XCTAssertTrue(canvas.erase(alongPath: gesture, brush: TestBrushes.hardRound, size: 16,
                                   opacity: 1, mode: .erase, seed: 0),
                      "Mode 1 has work to do on a strokeless layer")
        XCTAssertEqual(canvas.elements.filter { $0.stroke?.composite == .erase }.count, 1)

        guard let bytes = RasterVectorParity.premultipliedBytes(of: (try XCTUnwrap(canvas.render())), size: Self.canvasSize) else {
            return XCTFail("Could not read back the render")
        }
        // Under the gesture, inside the fill.
        let hole = (64 * Int(Self.canvasSize.width) + 64) * 4 + 3
        XCTAssertEqual(bytes[hole], 0, "The punch should go straight through the fill")
    }

    /// A gesture that never reaches anything must leave the list exactly as it was — no punch, and no
    /// spurious `changed` that would push an empty undo entry.
    func testAnEraseOverEmptySpaceChangesNothing() throws {
        let scene = scenario(brush: TestBrushes.hardRound,
                             eraserSamples: Self.ramp(from: CGPoint(x: 8, y: 8), to: CGPoint(x: 120, y: 8),
                                                      count: 9, from: 1, to: 1))
        let (canvas, _, changed) = try erased(scene)
        XCTAssertFalse(changed, "Nothing was under the gesture, so nothing changed")
        XCTAssertEqual(canvas.elements.count, 1)
        XCTAssertEqual(strokes(canvas, .erase).count, 0, "A punch over nothing must not be retained")
    }

    /// What re-erasing the same place actually costs, pinned rather than wished away.
    ///
    /// `inkTouched` asks about stroke *geometry*, not about ink still visible after earlier
    /// punches, so a second gesture over a stroke the eraser does not wholly cover retains a second punch. That is the
    /// design being consistent rather than leaking: an eraser **is** a stroke, and N eraser gestures
    /// cost N elements exactly as N paint gestures do. What
    /// `testErasingAStrokeAwayCompletelyLeavesAnEmptyDisplayList` covers is that an erase which
    /// fully resolves costs *nothing*, not that repeated scrubbing is free.
    ///
    /// So this pins the two properties that do hold: growth is one element per gesture (not one per
    /// stretch of backdrop, which is what the trimmed version produced), and stacking stays exact.
    func testReErasingTheSamePlaceCostsOneElementPerGestureAndStaysExact() throws {
        let scene = scenario(brush: TestBrushes.hardRound)
        let (canvas, _, _) = try erased(scene)
        XCTAssertEqual(strokes(canvas, .erase).count, 1)

        canvas.erase(alongPath: scene.eraserSamples, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase, seed: DabRandom.seed(for: scene.eraserID))
        XCTAssertEqual(strokes(canvas, .erase).count, 2,
                       "One gesture, one element — and never more than one")

        // Two identical full-opacity punches remove exactly what one does, so the render is still the
        // raster ground truth for a single erase.
        let texture = try RasterVectorParity.rasterBase(scene, backdrop: nil)
        RasterVectorParity.stamp(RasterVectorParity.paintStroke(scene), into: texture, isEraser: false)
        RasterVectorParity.stamp(RasterVectorParity.eraseStroke(scene), into: texture, isEraser: true)
        guard let report = RasterVectorParity.report(raster: try texture.renderToUIImage().get(),
                                                     vector: (try XCTUnwrap(canvas.render())),
                                                     size: scene.canvasSize) else {
            return XCTFail("Could not read back both tiers")
        }
        XCTAssertTrue(report.isExact, "Stacked punches must still be exact: \(report.diagnostic)")
    }

    /// A tap has no refit or chord/curve difference: only the field can move its scattered removal.
    /// Exercise the actual subtractive live scratch and the real Mode1 producer, then its saved list.
    func testModeOneKeepsTheLiveGestureFieldThroughCommitAndArchive() throws {
        var brush = TestBrushes.hardRound
        brush.dab.scatterAcross = 1
        let sample = VectorSample(x: 64, y: 64, pressure: 1)
        let run = StrokeSamples([sample], channels: .pressureOnly)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: Self.canvasSize), transform: nil),
                                     color: CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        for seed in [UInt64(0x84), 0x85] {
            let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill)])
            let before = try XCTUnwrap(canvas.render())
            func liveImage(seed: UInt64) throws -> UIImage {
                let texture = try CanvasFixture.rasterTexture(before, size: Self.canvasSize)
                let backdrop = CelContentPicture(size: Self.canvasSize,
                    window: CGRect(origin: .zero, size: Self.canvasSize), backing: nil, patch: nil,
                    ink: .rendered(before))
                let scratch = StrokeScratch(canvasSize: Self.canvasSize, role: .subtractive(backdrop: backdrop),
                                            texture: brush.texture)
                var walk = BrushStamper.LiveWalk(seed: seed)
                walk.stamp(to: sample, into: scratch, brush: brush, color: .black, brushSize: 8)
                walk.finish(into: scratch, brush: brush, color: .black, brushSize: 8)
                try scratch.commit(into: texture).get()
                return try texture.renderToUIImage().get()
            }
            let live = try liveImage(seed: seed)
            let wrongField = try XCTUnwrap(RasterVectorParity.report(
                raster: live, vector: try liveImage(seed: seed ^ 1), size: Self.canvasSize))
            XCTAssertFalse(wrongField.isExact, "PREMISE: this actual dab distinguishes the two fixed fields")
            XCTAssertTrue(canvas.erase(alongPath: run, brush: brush, size: 8, mode: .erase, seed: seed),
                          "PREMISE: the real Mode1 producer retains a punch over the fill")
            let committed = try XCTUnwrap(canvas.render())
            let report = try XCTUnwrap(RasterVectorParity.report(raster: live, vector: committed, size: Self.canvasSize))
            XCTAssertTrue(report.isExact, "Lift must retain the live removal: \(report.diagnostic)")
            let punch = try XCTUnwrap(canvas.elements.compactMap(\.stroke).first { $0.composite == .erase })
            XCTAssertEqual(punch.seed, seed, "The punch keeps the pen-down field independently of its new identity")

            let data = try JSONEncoder().encode(VectorCanvasData(from: canvas, imageFileNames: [:]))
            let decoded = try JSONDecoder().decode(VectorCanvasData.self, from: data)
            XCTAssertTrue(decoded.decodeReport.isClean, "PREMISE: the current saved display list decodes cleanly")
            let restored = VectorCanvas(size: Self.canvasSize, elements: try decoded.canvasSpaceElements(
                resolvingImages: { _ in nil }, resolvingVideos: { _ in nil }))
            XCTAssertEqual(restored.strokes.first { $0.composite == .erase }?.seed, seed,
                           "Save/load retains the gesture field")
            let reopened = try XCTUnwrap(RasterVectorParity.report(
                raster: committed, vector: try XCTUnwrap(restored.render()), size: Self.canvasSize))
            XCTAssertTrue(reopened.isExact, "The saved punch reopens without moving its removal: \(reopened.diagnostic)")
        }
    }

    func testFrozenVectorScratchSourceMatchesNonzeroCropAndExcludesReferenceStream() throws {
        let size = CGSize(width: 192, height: 160)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(x: 12, y: 18, width: 108, height: 86), transform: nil),
            color: CodableColor(red: 0.2, green: 0.7, blue: 0.35, alpha: 1))
        let stream = VectorStreamElement(naturalSize: CGSize(width: 24, height: 16), host: "fixture",
            port: 47301, sourceLabel: "reference", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 78, y: 70), scale: 1, rotation: 0))
        let canvas = VectorCanvas(size: size, elements: [.fill(fill), .stream(stream)])
        XCTAssertTrue(canvas.setStreamFrame(id: stream.id,
            image: UIGraphicsImageRenderer(size: stream.naturalSize, format: PixelOps.transparentFormat()).image { context in
                UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: stream.naturalSize))
            }, index: 1), "PREMISE: the contrasting red reference frame is present")
        let frozen = canvas.freeze(quality: .full)
        XCTAssertTrue(canvas.elements.contains(where: \.isReference), "PREMISE: a live reference crosses the tested crop")
        let picture = CelContentPicture(size: size, window: CGRect(origin: .zero, size: size),
            backing: nil, patch: nil, ink: .ordinary(source: frozen,
                elements: canvas.elements.withoutReference, rewriting: []))
        let window = CGRect(x: 43, y: 37, width: 74, height: 69)
        let cropped = try RasterSource.render(size: window.size) { context in
            picture.draw(into: context, content: CGRect(origin: CGPoint(x: -window.minX, y: -window.minY), size: size),
                         placement: .identity, replacing: true)
        }.get().resolveImage().get()
        let referenceFree = try XCTUnwrap(VectorCanvas(size: size, elements: [.fill(fill)]).render())
        let expectedCG = try XCTUnwrap(referenceFree.cgImage).cropping(to: window)
        let expected = UIImage(cgImage: try XCTUnwrap(expectedCG), scale: referenceFree.scale, orientation: .up)
        let parity = try XCTUnwrap(RasterVectorParity.report(raster: expected, vector: cropped, size: window.size))
        XCTAssertTrue(parity.isExact, "Nonzero-origin scratch source must match the equivalent frozen full-image crop: \(parity.diagnostic)")
    }

    func testSubtractiveCelDisplayMatchesCommittedInPlaceReferenceCoverage() throws {
        defer { PixelOps.clearRasterizeCache() }
        let size = CGSize(width: 128, height: 128)
        let stream = VectorStreamElement(naturalSize: CGSize(width: 20, height: 8), host: "fixture",
            port: 47301, sourceLabel: "reference", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 64, y: 12), scale: 1, rotation: 0))
        let paint = VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1), size: 12, opacity: 1,
            samples: StrokeSamples([VectorSample(x: 64, y: 64, pressure: 1)], channels: .pressureOnly), seed: 7)
        let eraserBrush = TestBrushes.hardRound
        let eraserSample = VectorSample(x: 64, y: 64, pressure: 1)
        let eraserSamples = StrokeSamples([eraserSample], channels: .pressureOnly)
        let sweep = try XCTUnwrap(VectorEraser.Sweep(samples: eraserSamples, brush: eraserBrush, size: 48))

        func composite(_ vector: VectorCanvas,
                       overlay: CelContentPicture.RenderedWindow? = nil) throws -> UIImage {
            var display = PixelOps.CelDisplay()
            display.vector = vector.freezeDisplay(referenceIDs: Set(vector.streams.filter(\.rendersInPlace).map(\.id)))
            if let overlay {
                display.drawOverlays = { cg, content in
                    overlay.draw(into: cg, content: content, canvasSize: size)
                    return true
                }
            }
            var cel = CanvasFixture.manager().layers[0].cels[0]
            cel.vector = vector
            let frozen = PixelOps.FrozenCel(cel: cel, derived: nil, quality: .full, display: display)
            return try XCTUnwrap(PixelOps.rasterize(frozen, canvasSize: size, quality: .full),
                                 "The CelDisplay rasterizer must produce the composed picture")
        }

        let referenceCases: [(name: String, position: CGPoint, intersectsCoverage: Bool,
                              fullyCovered: Bool)] = [
            ("outside", CGPoint(x: 64, y: 12), false, false),
            ("fully covered", CGPoint(x: 64, y: 64), true, true),
            ("partly covered", CGPoint(x: 86, y: 64), true, false)
        ]
        for referenceCase in referenceCases {
            for referenceAbovePaint in [false, true] {
                var placedStream = stream
                placedStream.transform = LayerTransform(position: referenceCase.position, scale: 1, rotation: 0)
                let elements: [VectorElement] = referenceAbovePaint
                    ? [.stroke(paint), .stream(placedStream)] : [.stream(placedStream), .stroke(paint)]
                let source = VectorCanvas(size: size, elements: elements)
                let referenceFrame = UIGraphicsImageRenderer(size: stream.naturalSize,
                    format: PixelOps.transparentFormat()).image { context in
                        UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: stream.naturalSize))
                    }
                XCTAssertTrue(source.setStreamFrame(id: stream.id, image: referenceFrame, index: 1),
                              "PREMISE: the in-place reference frame is available")
                let referenceWindow = try XCTUnwrap(source.streamWindow(id: stream.id))
                XCTAssertEqual(sweep.touches(region: CGPath(rect: referenceWindow, transform: nil)),
                               referenceCase.intersectsCoverage,
                               "PREMISE: the \(referenceCase.name) reference has the expected sweep relationship")
                XCTAssertGreaterThan(source.strokes.count, 0, "PREMISE: editable ink exists before erasing")
                let before = try XCTUnwrap(source.render())
                let beforeBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: before, size: size))
                let paintOffset = (64 * Int(size.width) + 64) * 4
                XCTAssertGreaterThan(beforeBytes[paintOffset + 3], 240,
                                     "PREMISE: the editable mark is visible before erasing")

                let references = Set(source.streams.filter(\.rendersInPlace).map(\.id))
                let sourceElements = source.elements
                let displayInk = CelContentPicture.Ink.ordinary(
                    source: source.freezeDisplay(referenceIDs: references),
                    elements: sourceElements, rewriting: [])
                let backdrop = CelContentPicture(size: size, window: CGRect(origin: .zero, size: size),
                    backing: nil, patch: nil, ink: displayInk)
                let scratch = StrokeScratch(canvasSize: size, role: .subtractive(backdrop: backdrop),
                    celContent: StrokeScratch.CelContent(backing: nil, ink: displayInk, placement: .identity))
                var liveWalk = BrushStamper.LiveWalk(seed: 9)
                liveWalk.stamp(to: eraserSample, into: scratch, brush: eraserBrush, color: .black, brushSize: 48)
                liveWalk.finish(into: scratch, brush: eraserBrush, color: .black, brushSize: 48)
                let shown = try XCTUnwrap(scratch.renderedCelContent,
                                          "PREMISE: the live scratch resolves a window picture")
                XCTAssertTrue(scratch.windowRect.contains(CGPoint(x: referenceWindow.midX, y: referenceWindow.midY)),
                              "PREMISE: the reference test pixel lies inside the scratch window")

                let committed = VectorCanvas(size: size, elements: source.elements)
                XCTAssertTrue(committed.erase(alongPath: eraserSamples, brush: eraserBrush, size: 48,
                                               opacity: 1, mode: .erase, seed: 9),
                              "PREMISE: the real Mode 1 producer deletes the covered editable stroke")
                XCTAssertEqual(committed.strokes.filter { $0.composite == .paint }.count, 0,
                               "PREMISE: the covered own stroke is gone from the committed model")
                XCTAssertEqual(committed.strokes.filter { $0.composite == .erase }.count,
                               referenceCase.intersectsCoverage ? 1 : 0,
                               "PREMISE: a retained punch exists only when it also covers the reference")
                XCTAssertEqual(committed.streams.count, 1, "PREMISE: the in-place reference remains in the model")

                let expected = try composite(committed)
                let expectedBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: expected, size: size))
                let referenceX = Int(referenceWindow.midX), referenceY = Int(referenceWindow.midY)
                let referenceOffset = (referenceY * Int(size.width) + referenceX) * 4
                if !referenceCase.intersectsCoverage {
                    XCTAssertGreaterThan(expectedBytes[referenceOffset], 220,
                                         "PREMISE: committed display retains the untouched red reference")
                    XCTAssertLessThan(expectedBytes[referenceOffset + 1], 64)
                } else if referenceCase.fullyCovered {
                    XCTAssertLessThan(expectedBytes[referenceOffset + 3], 16,
                                      "PREMISE: the committed erase punch removes the fully covered reference")
                } else {
                    let coveredOffset = (referenceY * Int(size.width) + 80) * 4
                    let uncoveredOffset = (referenceY * Int(size.width) + 92) * 4
                    XCTAssertLessThan(expectedBytes[coveredOffset + 3], 16,
                                      "PREMISE: the punch removes the partly covered reference edge")
                    XCTAssertGreaterThan(expectedBytes[uncoveredOffset], 220,
                                         "PREMISE: the uncovered reference edge remains red")
                }

                let actual = try composite(source, overlay: shown)
                let actualBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: actual, size: size))
                let parity = try XCTUnwrap(RasterVectorParity.report(raster: expected, vector: actual, size: size))
                XCTAssertTrue(parity.isExact,
                              "The live scratch must match the committed display (reference=\(referenceCase.name), referenceAbovePaint=\(referenceAbovePaint)): \(parity.diagnostic)")
                XCTAssertEqual(Array(actualBytes[referenceOffset..<(referenceOffset + 4)]),
                               Array(expectedBytes[referenceOffset..<(referenceOffset + 4)]),
                               "The reference pixel must match committed display ordering and erase coverage")
                if !referenceCase.fullyCovered, referenceCase.intersectsCoverage {
                    let coveredOffset = (referenceY * Int(size.width) + 80) * 4
                    let uncoveredOffset = (referenceY * Int(size.width) + 92) * 4
                    XCTAssertEqual(actualBytes[coveredOffset + 3], expectedBytes[coveredOffset + 3])
                    XCTAssertEqual(actualBytes[uncoveredOffset], expectedBytes[uncoveredOffset],
                                   "The surviving reference edge must retain committed red")
                }
            }
        }
    }

    func testModeTwoAndFourScratchMatchCommittedReferenceOrdering() throws {
        defer { PixelOps.clearRasterizeCache() }
        let size = Self.canvasSize
        let paintSamples = Self.ramp(from: CGPoint(x: 24, y: 64), to: CGPoint(x: 104, y: 64),
                                     count: 9, from: 1, to: 1)
        let paint = VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1), size: 16, opacity: 1,
            samples: paintSamples, seed: 17)
        let brush = TestBrushes.hardRound
        let modeCases: [(name: String, mode: VectorEraserMode, samples: StrokeSamples, size: CGFloat)] = [
            ("cut points", .cutPoints,
             Self.ramp(from: CGPoint(x: 64, y: 32), to: CGPoint(x: 64, y: 96), count: 9, from: 1, to: 1), 16),
            ("whole stroke", .wholeStroke,
             StrokeSamples([VectorSample(x: 64, y: 64, pressure: 1)], channels: .pressureOnly), 112)
        ]
        let referenceCases: [(name: String, position: CGPoint)] = [
            ("outside changed ink and sweep", CGPoint(x: 12, y: 12)),
            ("over changed ink", CGPoint(x: 42, y: 64))
        ]

        func composite(_ vector: VectorCanvas,
                       overlay: CelContentPicture.RenderedWindow? = nil) throws -> UIImage {
            var display = PixelOps.CelDisplay()
            display.vector = vector.freezeDisplay(referenceIDs: Set(vector.streams.filter(\.rendersInPlace).map(\.id)))
            if let overlay {
                display.drawOverlays = { cg, content in
                    overlay.draw(into: cg, content: content, canvasSize: size)
                    return true
                }
            }
            var cel = CanvasFixture.manager().layers[0].cels[0]
            cel.vector = vector
            let frozen = PixelOps.FrozenCel(cel: cel, derived: nil, quality: .full, display: display)
            return try XCTUnwrap(PixelOps.rasterize(frozen, canvasSize: size, quality: .full),
                                 "The CelDisplay rasterizer must produce the composed picture")
        }

        for modeCase in modeCases {
            for referenceCase in referenceCases {
                for referenceAbovePaint in [false, true] {
                    let stream = VectorStreamElement(naturalSize: CGSize(width: 20, height: 8), host: "fixture",
                        port: 47301, sourceLabel: "reference", rendersInPlace: true,
                        transform: LayerTransform(position: referenceCase.position, scale: 1, rotation: 0))
                    let elements: [VectorElement] = referenceAbovePaint
                        ? [.stroke(paint), .stream(stream)] : [.stream(stream), .stroke(paint)]
                    let source = VectorCanvas(size: size, elements: elements)
                    let frame = UIGraphicsImageRenderer(size: stream.naturalSize,
                        format: PixelOps.transparentFormat()).image { context in
                            UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: stream.naturalSize))
                        }
                    XCTAssertTrue(source.setStreamFrame(id: stream.id, image: frame, index: 1),
                                  "PREMISE: the in-place reference frame is available")
                    XCTAssertGreaterThan(source.strokes.count, 0, "PREMISE: own ink exists before preview")

                    let before = try XCTUnwrap(source.render())
                    let beforeBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: before, size: size))
                    let ownInkOffset = (64 * Int(size.width) + 40) * 4
                    XCTAssertGreaterThan(beforeBytes[ownInkOffset + 3], 240,
                                         "PREMISE: the editable stroke is visible before preview")

                    let references = Set(source.streams.filter(\.rendersInPlace).map(\.id))
                    let sourceElements = source.elements
                    let displayInk = CelContentPicture.Ink.ordinary(
                        source: source.freezeDisplay(referenceIDs: references),
                        elements: sourceElements, rewriting: [])
                    let scratch = StrokeScratch(canvasSize: size, role: .replacing,
                        celContent: StrokeScratch.CelContent(backing: nil, ink: displayInk, placement: .identity))

                    let previewResult: VectorCanvas.EraserPreview?
                    switch modeCase.mode {
                    case .cutPoints:
                        var progress: [UUID: VectorCanvas.CutPreviewProgress] = [:]
                        previewResult = source.cutPreviewElements(alongPath: modeCase.samples, brush: brush,
                            size: modeCase.size, accumulating: &progress)
                    case .wholeStroke:
                        var doomed: Set<UUID> = []
                        previewResult = source.wholeStrokePreviewElements(alongPath: modeCase.samples, brush: brush,
                            size: modeCase.size, accumulating: &doomed)
                    case .erase, .cutToIntersection:
                        XCTFail("The fixture only covers Mode 2 and Mode 4")
                        previewResult = nil
                    }
                    let preview = try XCTUnwrap(previewResult, "PREMISE: geometry mode produces an ordered preview")
                    switch modeCase.mode {
                    case .cutPoints:
                        XCTAssertFalse(preview.rewriting.isEmpty, "PREMISE: Mode 2 rewrites a cut stroke")
                    case .wholeStroke:
                        XCTAssertEqual(preview.rewriting, Set([paint.id]),
                                       "PREMISE: Mode 4 previews the own stroke once")
                    case .erase, .cutToIntersection:
                        XCTFail("The fixture only covers Mode 2 and Mode 4")
                    }
                    XCTAssertTrue(preview.rewriting.contains(paint.id), "PREMISE: own stroke is rewritten")
                    XCTAssertTrue(scratch.replaceVectorDisplay(elements: preview.elements,
                        rewriting: preview.rewriting, damage: preview.damage, revision: 1),
                        "PREMISE: the changed list is admitted into the bounded scratch window")
                    scratch.settleCelContent()
                    let shown = try XCTUnwrap(scratch.renderedCelContent,
                        "PREMISE: the Mode 2/4 scratch resolves its bounded replacement picture")
                    let referenceWindow = try XCTUnwrap(source.streamWindow(id: stream.id))
                    XCTAssertTrue(scratch.windowRect.contains(CGPoint(x: referenceWindow.midX,
                                                                       y: referenceWindow.midY)),
                                  "PREMISE: the reference is inside the changed scratch window")

                    let committed = VectorCanvas(size: size, elements: source.elements)
                    XCTAssertTrue(committed.erase(alongPath: modeCase.samples, brush: brush,
                        size: modeCase.size, opacity: 1, mode: modeCase.mode, seed: 19),
                        "PREMISE: the real Mode 2/4 commit changes own geometry")
                    XCTAssertEqual(committed.strokes.filter { $0.composite == .paint }.count,
                                   modeCase.mode == .cutPoints ? 2 : 0,
                                   "PREMISE: committed Mode 2 cuts into pieces; Mode 4 removes the whole stroke")
                    XCTAssertEqual(committed.strokes.filter { $0.composite == .erase }.count, 0,
                                   "PREMISE: geometry modes retain no erase punch")
                    XCTAssertEqual(committed.streams.count, 1, "PREMISE: commit retains the reference element")

                    let expected = try composite(committed)
                    let expectedBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: expected, size: size))
                    let refX = Int(referenceWindow.midX), refY = Int(referenceWindow.midY)
                    let refOffset = (refY * Int(size.width) + refX) * 4
                    if referenceCase.name == "over changed ink", modeCase.mode == .cutPoints,
                       !referenceAbovePaint {
                        XCTAssertGreaterThan(expectedBytes[refOffset + 2], 180,
                            "PREMISE: the surviving paint remains above a reference below it")
                    } else {
                        XCTAssertGreaterThan(expectedBytes[refOffset], 220,
                            "PREMISE: committed \(modeCase.name) display keeps the exposed reference red")
                        XCTAssertLessThan(expectedBytes[refOffset + 1], 64)
                    }

                    let actual = try composite(source, overlay: shown)
                    let parity = try XCTUnwrap(RasterVectorParity.report(raster: expected, vector: actual, size: size))
                    XCTAssertTrue(parity.isExact,
                        "Live \(modeCase.name) scratch must match committed reference order (\(referenceCase.name), referenceAbovePaint=\(referenceAbovePaint)): \(parity.diagnostic)")
                }
            }
        }
    }

    func testFullWindowInkPatchDoesNotResurrectFrozenInkThroughTransparentPixels() throws {
        let size = CGSize(width: 96, height: 80)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
            color: CodableColor(red: 0.05, green: 0.2, blue: 0.95, alpha: 1))
        let canvas = VectorCanvas(size: size, elements: [.fill(fill)])
        let frozen = canvas.freeze(quality: .full)
        let window = CGRect(x: 30, y: 24, width: 32, height: 28)
        let patch = UIGraphicsImageRenderer(size: window.size, format: PixelOps.transparentFormat()).image { renderer in
            let cg = renderer.cgContext
            UIColor.red.setFill()
            cg.fill(CGRect(origin: .zero, size: window.size))
            cg.clear(CGRect(x: 12, y: 10, width: 8, height: 8))
        }
        let picture = CelContentPicture(size: size, window: window, backing: nil, patch: nil,
            ink: .ordinary(source: frozen, elements: canvas.elements.withoutReference, rewriting: []),
            inkPatch: patch)
        let output = try RasterSource.render(size: size) { context in
            picture.draw(into: context, content: CGRect(origin: .zero, size: size),
                         placement: .identity, replacing: true)
        }.get().resolveImage().get()
        let bytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: output, size: size))
        let patchBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: patch, size: window.size))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = (y * Int(size.width) + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
        let source = try XCTUnwrap(RasterVectorParity.premultipliedBytes(
            of: try XCTUnwrap(canvas.render()), size: size))
        let hole = pixel(Int(window.minX) + 15, Int(window.minY) + 13)
        let patched = pixel(Int(window.minX) + 4, Int(window.minY) + 4)
        let outside = pixel(8, 8)
        let sourceOffset = (Int(window.minY + 13) * Int(size.width) + Int(window.minX + 15)) * 4
        let patchHoleOffset = (13 * Int(window.width) + 15) * 4
        let patchOpaqueOffset = (4 * Int(window.width) + 4) * 4
        XCTAssertGreaterThan(source[sourceOffset + 3],
                             240, "PREMISE: frozen blue ink exists under the transparent patch pixel")
        XCTAssertLessThan(patchBytes[patchHoleOffset + 3], 16, "PREMISE: the patch is transparent at the hole")
        XCTAssertGreaterThan(patchBytes[patchOpaqueOffset], 220, "PREMISE: the patch is red outside the hole")
        XCTAssertLessThan(hole[3], 16,
                          "A transparent pixel in a full-window replacement must not reveal frozen pre-edit ink")
        XCTAssertGreaterThan(patched[0], 220, "The opaque patch pixel must replace the frozen source")
        XCTAssertGreaterThan(patched[3], 240, "The opaque patch pixel remains fully covered")
        XCTAssertLessThan(outside[3], 16, "The replacement leaves pixels outside its footprint untouched")
    }

    func testModeThreeCommittedCutsStayExactInOneBoundedWindow() throws {
        let size = CGSize(width: 512, height: 512)
        let victims = [CGFloat(32), 64, 96].map { x in
            VectorStroke(brush: TestBrushes.hardRound,
                color: CodableColor(red: 0.1, green: 0.3, blue: 0.95, alpha: 1), size: 8, opacity: 1,
                samples: StrokeSamples([VectorSample(x: x, y: 24, pressure: 1),
                                        VectorSample(x: x, y: 104, pressure: 1)], channels: .pressureOnly),
                seed: 23)
        }
        let reference = VectorStreamElement(naturalSize: CGSize(width: 18, height: 10), host: "fixture",
            port: 47301, sourceLabel: "Mode 3 window reference", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: 64, y: 64), scale: 1, rotation: 0))
        let source = VectorCanvas(size: size,
            elements: [VectorElement.stream(reference)] + victims.map { VectorElement.stroke($0) })
        let referenceImage = UIGraphicsImageRenderer(size: reference.naturalSize,
            format: PixelOps.transparentFormat()).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(origin: .zero, size: reference.naturalSize))
            }
        XCTAssertTrue(source.setStreamFrame(id: reference.id, image: referenceImage, index: 1),
                      "PREMISE: the captured in-place reference is available")
        _ = try XCTUnwrap(source.render(), "PREMISE: an ordinary displayed cel has its real base memo")
        let baseRasterizations = source.rasterizations
        let original = source.elements
        let frozen = source.freezeDisplay(referenceIDs: [reference.id])
        let scratch = StrokeScratch(canvasSize: size, role: .replacing,
            celContent: StrokeScratch.CelContent(backing: nil,
                ink: .ordinary(source: frozen, elements: original, rewriting: []), placement: .identity))
        var driver = VectorEraser.IntersectionDriver()
        var damage = CGRect.null
        var firstWindow: CGRect?

        for point in [CGPoint(x: 32, y: 64), CGPoint(x: 64, y: 64), CGPoint(x: 96, y: 64)] {
            let result = source.cutToIntersection(atCanvasPoint: point, brush: TestBrushes.hardRound,
                                                  size: 16, suppressing: driver.suppressed)
            driver.accept(result.outcome, underTip: result.underTip)
            guard case .cut = result.outcome else {
                XCTFail("PREMISE: each separated Mode 3 target is cut on its sample")
                return
            }
            guard case .region(let changed) = source.lastDamage else {
                XCTFail("PREMISE: each committed cut reports bounded region damage")
                return
            }
            damage = damage.isNull ? changed : damage.union(changed)
            XCTAssertTrue(scratch.replaceVectorDisplay(elements: source.elements, rewriting: [], damage: damage, revision: 1),
                          "The current ordered list must publish after each real cut")
            scratch.settleCelContent()
            XCTAssertTrue(scratch.hasCurrentReplacementWindow(covering: damage),
                          "The same owner query used by the view accepts each successfully rendered window")
            let shown = try XCTUnwrap(scratch.renderedCelContent)
            XCTAssertTrue(shown.window.contains(damage), "The admitted window covers all cuts so far")
            XCTAssertEqual(scratch.windowPixelCount, 0,
                           "Mode 3 uses the native replacement image without a second raster scratch")
            if let firstWindow {
                XCTAssertTrue(shown.window.contains(firstWindow),
                              "A later cut grows the same geometric window around prior admitted damage")
            } else {
                firstWindow = shown.window
            }
            XCTAssertLessThan(shown.window.width * shown.window.height, size.width * size.height,
                              "Separated cuts keep the presentation local to their measured damage")

            let committed = VectorCanvas(size: size, elements: source.elements)
            let expected = try XCTUnwrap(committed.freezeDisplay(referenceIDs: [reference.id]).render(quality: .full))
            let crop = try XCTUnwrap(expected.cgImage?.cropping(to: shown.window))
            let expectedWindow = UIImage(cgImage: crop, scale: expected.scale, orientation: .up)
            let parity = try XCTUnwrap(RasterVectorParity.report(raster: expectedWindow,
                                                                  vector: shown.image, size: shown.window.size))
            XCTAssertTrue(parity.isExact, "Every intermediate replacement matches the committed list: \(parity.diagnostic)")
        }

        XCTAssertEqual(source.strokes.count, 0, "PREMISE: all three per-sample cuts committed")
        let finalCanvas = VectorCanvas(size: size, elements: source.elements)
        let finalDisplay = try XCTUnwrap(finalCanvas.freezeDisplay(referenceIDs: [reference.id]).render(quality: .full))
        let finalBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: finalDisplay, size: size))
        let referenceOffset = (64 * Int(size.width) + 64) * 4
        XCTAssertGreaterThan(finalBytes[referenceOffset], 220,
                             "The captured reference remains visible in its original display-list slot")
        XCTAssertLessThan(finalBytes[referenceOffset + 1], 64)
        XCTAssertEqual(source.rasterizations, baseRasterizations,
                       "Successful cuts add no full-canvas rasterization beyond the already visible base")
        if case .needsRasterize = source.cachedRender() {} else {
            XCTFail("The bounded preview leaves the live canvas memo invalidated for the normal lift render")
        }
        let lastWindow = try XCTUnwrap(scratch.renderedCelContent)
        XCTAssertNotNil(firstWindow)
        XCTAssertFalse(scratch.hasCurrentReplacementWindow(covering: .null),
                       "Unknown damage must never validate an otherwise healthy replacement window")
        let unrelatedDamage = CGRect(x: 400, y: 400, width: 8, height: 8)
        XCTAssertFalse(scratch.windowRect.contains(unrelatedDamage), "PREMISE: this separate damage is outside the admitted window")
        XCTAssertFalse(scratch.hasCurrentReplacementWindow(covering: unrelatedDamage),
                       "A window is not current for pixels outside its admitted bounds")
        // Off main, the call admits the growth and the lift's settle finds the source refuses it; the
        // last valid picture must survive that.
        _ = scratch.replaceCelContent(
            ink: .derived(DerivedCelContent(identity: "mode3-refused-growth", render: { _, _ in nil }), .full),
            damage: CGRect(x: 112, y: 48, width: 8, height: 32), revision: 2)
        scratch.settleCelContent()
        XCTAssertTrue(scratch.windowRect.contains(damage), "A refused growth retains the last admitted window")
        XCTAssertFalse(scratch.hasCurrentReplacementWindow(covering: damage),
                       "A retained old picture after failed growth is not a current replacement")
        XCTAssertTrue(scratch.renderedCelContent?.image === lastWindow.image,
                      "The retained image is stale after refusal and production must fall back to the canvas render")
        if case .failure = scratch.lastMutationResult {} else {
            XCTFail("The refused growth must stay latched so the old image is not treated as current")
        }
    }

    func testConsecutiveToCrossCutsSeedFreshFragmentBoundsWithoutCanvasRender() throws {
        let size = CGSize(width: 512, height: 384)
        let samples = StrokeSamples((0..<65).map { index -> VectorSample in
            let t = CGFloat(index) / 64
            return VectorSample(x: 256, y: 20 + 344 * t, pressure: 0.45 + 0.55 * t)
        }, channels: .pressureOnly)
        let victim = VectorStroke(brush: TestBrushes.square,
            color: CodableColor(red: 0.08, green: 0.24, blue: 0.92, alpha: 1),
            size: 18, opacity: 1, samples: samples, seed: 0xD06F_2026)
        // Each pair brackets one cut, but stays farther away than the 12 pt nib radius.
        let barriers = [64, 160, 224, 304].map { row in
            let y = CGFloat(row)
            return VectorStroke(brush: TestBrushes.hardRound,
                color: CodableColor(red: 0.12, green: 0.82, blue: 0.18, alpha: 1),
                size: 4, opacity: 1,
                samples: StrokeSamples([VectorSample(x: 180, y: y, pressure: 1),
                                        VectorSample(x: 332, y: y, pressure: 1)], channels: .pressureOnly),
                seed: UInt64(row) + 0xB411_1E2)
        }
        let source = VectorCanvas(size: size,
            elements: [.stroke(victim)] + barriers.map { VectorElement.stroke($0) })
        let originalImage = try XCTUnwrap(source.render(),
                                          "PREMISE: the displayed source has measured victim/barrier bounds")
        let baseRasterizations = source.rasterizations
        let originalBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: originalImage, size: size))
        let retainedInk = (40 * Int(size.width) + 256) * 4
        let crossingInk = (64 * Int(size.width) + 256) * 4
        XCTAssertGreaterThan(originalBytes[retainedInk + 2], 200,
                             "PREMISE: the custom square-tip victim has visible ink outside both cuts")
        XCTAssertGreaterThan(originalBytes[retainedInk + 3], 240)
        XCTAssertGreaterThan(originalBytes[crossingInk + 1], 180,
                             "PREMISE: the green crossing barriers are visibly drawn")
        XCTAssertGreaterThan(originalBytes[crossingInk + 3], 240)

        let firstCut = source.cutToIntersection(atCanvasPoint: CGPoint(x: 256, y: 104),
                                                brush: TestBrushes.hardRound, size: 24)
        XCTAssertEqual(firstCut.outcome, .cut, "PREMISE: the first nib removes the span between y64 and y160")
        guard case .region = source.lastDamage else {
            XCTFail("The measured original stroke must keep the first cut bounded, got \(source.lastDamage)")
            return
        }
        let idsBeforeFirstCut = Set([victim.id] + barriers.map(\.id))
        let firstFragmentIDs = Set(source.strokes.map(\.id)).subtracting(idsBeforeFirstCut)
        XCTAssertEqual(firstFragmentIDs.count, 2,
                       "PREMISE: the first cut leaves two fresh fragments of the original stroke")
        XCTAssertEqual(source.strokes.count, 6, "The first cut keeps four barriers and two victim fragments")
        XCTAssertEqual(source.rasterizations, baseRasterizations,
                       "No canvas render may warm the fresh fragments before the next cut")

        let secondPoint = CGPoint(x: 256, y: 244)
        let secondVictim = try XCTUnwrap(source.topmostStroke(atCanvasPoint: secondPoint, slop: 0),
                                         "PREMISE: the second nib lands on a surviving victim fragment")
        XCTAssertTrue(firstFragmentIDs.contains(secondVictim.id),
                      "PREMISE: the second cut targets an ID minted by the first cut")
        let secondCut = source.cutToIntersection(atCanvasPoint: secondPoint,
                                                 brush: TestBrushes.hardRound, size: 24)
        XCTAssertEqual(secondCut.outcome, .cut,
                       "PREMISE: the second nib removes the span between y224 and y304")
        guard case .region(let secondDamage) = source.lastDamage else {
            XCTFail("A freshly measured fragment must keep the second cut local, got \(source.lastDamage)")
            return
        }
        XCTAssertLessThan(secondDamage.width * secondDamage.height, size.width * size.height / 4,
                          "The second cut stays bounded without an intervening source render")
        XCTAssertEqual(source.rasterizations, baseRasterizations,
                       "The second cut cannot rely on a canvas render to measure its new victim")

        XCTAssertEqual(source.strokes.count, 7,
                       "Two cuts leave three victim fragments while preserving four barriers")
        let incremental = try XCTUnwrap(source.render(), "The final edited list takes one region repair")
        let committed = VectorCanvas(size: size, elements: source.elements)
        let expected = try XCTUnwrap(committed.render(), "PREMISE: an independent full render is available")
        let report = try XCTUnwrap(RasterVectorParity.report(raster: expected, vector: incremental, size: size))
        XCTAssertLessThanOrEqual(report.maxChannelDelta, 2,
                                 "The locally repaired picture matches the full committed render: \(report.diagnostic)")
        XCTAssertEqual(source.regionRepairs, 1, "Both consecutive cuts share one bounded base repair")
        XCTAssertEqual(source.regionRepairsWidened, 0, "Measured fragments keep the declared region sufficient")
        let bytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: incremental, size: size))
        XCTAssertGreaterThan(bytes[retainedInk + 2], 200,
                             "The retained square-tip stroke remains visible after both cuts")
        XCTAssertGreaterThan(bytes[retainedInk + 3], 240)
    }

    func testScratchRefusedDisplaySourcePublishesNoWindowAndReturnsFailure() {
        let size = CGSize(width: 32, height: 32)
        let scratch = StrokeScratch(canvasSize: size, role: .replacing,
            celContent: StrokeScratch.CelContent(backing: nil,
                ink: .rendered(UIImage()), placement: .identity))
        let refused = scratch.replaceCelContent(
            ink: .derived(DerivedCelContent(identity: "refused-source", render: { _, _ in nil }), .full),
            damage: CGRect(x: 8, y: 8, width: 8, height: 8), revision: 1)
        // The render is off main now, so the call cannot know the source refuses: it is admitted, and the
        // refusal is what the lift's settle finds.
        _ = refused
        scratch.settleCelContent()
        XCTAssertNil(scratch.renderedCelContent, "A refused source publishes no rendered picture")
        XCTAssertNil(scratch.image, "A refused source cannot publish a preview image")
        if case .success = scratch.lastMutationResult {
            XCTFail("The scratch must retain the source failure")
        }
    }

    func testSmallScratchDrawDoesNotRasterizeOrMemoizeTheFullCanvas() throws {
        let size = CGSize(width: 2048, height: 2048)
        let fill = VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 8, width: 32, height: 32), transform: nil),
            color: CodableColor(red: 0.1, green: 0.35, blue: 0.9, alpha: 1))
        let distantFill = VectorFillElement(path: CGPath(rect: CGRect(x: 700, y: 700, width: 32, height: 32), transform: nil),
            color: CodableColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1))
        let elements: [VectorElement] = [.fill(fill), .fill(distantFill)]
        let canvas = VectorCanvas(size: size, elements: elements)
        XCTAssertEqual(canvas.rasterizations, 0)
        if case .needsRasterize = canvas.cachedRender() {} else {
            XCTFail("PREMISE: this nonempty canvas has no full-image memo")
        }
        let frozen = canvas.freeze(quality: .full)
        let scratch = StrokeScratch(canvasSize: size, role: .replacing,
            celContent: StrokeScratch.CelContent(backing: nil,
                ink: .ordinary(source: frozen, elements: [.fill(fill)], rewriting: [distantFill.id]),
                placement: .identity))
        XCTAssertTrue(scratch.replaceCelContent(
            ink: .ordinary(source: frozen, elements: [.fill(fill)], rewriting: [distantFill.id]),
            damage: CGRect(x: 8, y: 8, width: 32, height: 32), revision: 1))
        XCTAssertFalse(scratch.windowRect.isNull, "A changed native list publishes an admitted presentation window")
        XCTAssertGreaterThan(scratch.windowRect.width, 0)
        XCTAssertGreaterThan(scratch.windowRect.height, 0)
        XCTAssertEqual(scratch.windowPixelCount, 0,
                       "Native replacement must not allocate a second raster scratch")
        scratch.settleCelContent()
        let first = try XCTUnwrap(scratch.renderedCelContent,
                                  "The first damage rectangle publishes its rendered window")
        XCTAssertLessThan(first.window.width * first.window.height, 256 * 256,
                          "The first native replacement window stays local on the large canvas")

        XCTAssertTrue(scratch.replaceCelContent(
            ink: .ordinary(source: frozen, elements: elements, rewriting: Set(elements.map(\.id))),
            damage: CGRect(x: 700, y: 700, width: 32, height: 32), revision: 2),
            "A later edit grows the existing geometric window without creating a raster scratch")
        scratch.settleCelContent()
        let grown = try XCTUnwrap(scratch.renderedCelContent)
        XCTAssertGreaterThan(grown.window.width, first.window.width)
        XCTAssertGreaterThan(grown.window.height, first.window.height)
        XCTAssertTrue(grown.window.contains(first.window),
                      "The grown replacement window retains the first admitted window")
        XCTAssertLessThan(grown.window.width * grown.window.height, size.width * size.height,
                          "Growth remains smaller than the canvas for separated local edits")
        XCTAssertEqual(scratch.windowPixelCount, 0,
                       "Geometric growth must not allocate an ignored raster window")
        let bytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: grown.image,
                                                                         size: grown.window.size))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = (y * Int(grown.window.width) + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
        let firstProbe = CGPoint(x: 12, y: 12)
        let distantProbe = CGPoint(x: 704, y: 704)
        let containsBothProbes = grown.window.contains(firstProbe) && grown.window.contains(distantProbe)
        XCTAssertTrue(containsBothProbes, "Both retained fills must lie inside the grown window before pixel reads")
        guard containsBothProbes else { return }
        let firstPixel = pixel(Int(firstProbe.x) - Int(grown.window.minX),
                               Int(firstProbe.y) - Int(grown.window.minY))
        let distantPixel = pixel(Int(distantProbe.x) - Int(grown.window.minX),
                                 Int(distantProbe.y) - Int(grown.window.minY))
        XCTAssertGreaterThan(firstPixel[3], 240, "Growth retains the first admitted source pixels")
        XCTAssertGreaterThan(firstPixel[2], firstPixel[0], "The first visible fill keeps its blue color")
        XCTAssertGreaterThan(distantPixel[3], 240, "The newly admitted distant fill is visible")
        XCTAssertGreaterThan(distantPixel[1], distantPixel[0], "The distant fill keeps its green color")
        XCTAssertEqual(canvas.rasterizations, 0, "The scratch draw must not create a canvas-sized render")
        if case .needsRasterize = canvas.cachedRender() {} else {
            XCTFail("The window source must not fill the live canvas memo")
        }
    }

    func testNativeReplacementKeepsIndependentPosesAndHeldWindowImmutable() throws {
        let size = CGSize(width: 256, height: 256)
        let victim = VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.05, green: 0.2, blue: 0.95, alpha: 1), size: 8, opacity: 1,
            samples: StrokeSamples([VectorSample(x: 40, y: 100, pressure: 1),
                                    VectorSample(x: 80, y: 100, pressure: 1)], channels: .pressureOnly), seed: 13)
        let canvas = VectorCanvas(size: size, elements: [.stroke(victim)])
        let original = canvas.elements
        _ = canvas.render()
        let frozen = canvas.freezeDisplay(referenceIDs: [])
        let backing = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 32, y: 92, width: 56, height: 16))
        }
        let snapshot = try XCTUnwrap(CelPixelSnapshot(capturing: nil, baked: backing, size: size))
        let placement = CelContentPlacement(
            ink: PoseMap(CGAffineTransform(translationX: 80, y: 0)),
            backing: PoseMap(CGAffineTransform(translationX: 0, y: 32)))
        let sourceInk = CelContentPicture.Ink.ordinary(source: frozen, elements: original, rewriting: [])
        let scratch = StrokeScratch(canvasSize: size, role: .replacing,
            celContent: StrokeScratch.CelContent(backing: snapshot, ink: sourceInk, placement: placement))
        let damage = CGRect(x: 32, y: 92, width: 56, height: 16)

        XCTAssertTrue(scratch.replaceVectorDisplay(elements: [], rewriting: [victim.id], damage: damage, revision: 1),
                      "The fully removed editable stroke publishes its bounded native replacement")
        scratch.settleCelContent()
        let first = try XCTUnwrap(scratch.renderedCelContent)
        XCTAssertTrue(first.window.contains(CGPoint(x: 40, y: 130)),
                      "PREMISE: independently posed backing is inside the replacement footprint")
        XCTAssertTrue(first.window.contains(CGPoint(x: 140, y: 100)),
                      "PREMISE: posed ink space is also inside the replacement footprint")
        let firstBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: first.image,
                                                                            size: first.window.size))
        func pixel(_ bytes: [UInt8], window: CGRect, x: Int, y: Int) -> [UInt8] {
            let offset = ((y - Int(window.minY)) * Int(window.width) + x - Int(window.minX)) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
        let backingPixel = pixel(firstBytes, window: first.window, x: 40, y: 130)
        XCTAssertGreaterThan(backingPixel[0], 220, "The raster backing follows its own vertical pose")
        XCTAssertLessThan(pixel(firstBytes, window: first.window, x: 40, y: 100)[3], 16,
                          "The backing does not inherit the editable ink's distinct pose")

        var held = UnlandedInk()
        held.hold(.init(id: 1, version: canvas.version, windowRect: first.window,
                        replacing: first.footprint, contents: .image(first.image)))
        guard let heldPicture = held.pictures.first,
              case .image(let heldImage) = heldPicture.contents,
              let heldBytes = RasterVectorParity.premultipliedBytes(of: heldImage, size: first.window.size) else {
            return XCTFail("The existing held-picture path must retain the admitted window image")
        }

        let replacement = VectorStroke(brush: TestBrushes.hardRound,
            color: CodableColor(red: 0.05, green: 0.9, blue: 0.15, alpha: 1), size: 8, opacity: 1,
            samples: victim.samples, seed: victim.seed)
        XCTAssertTrue(scratch.replaceVectorDisplay(elements: [.stroke(replacement)], rewriting: [victim.id],
                                                    damage: damage, revision: 2),
                      "A later geometry update replaces the current presentation")
        scratch.settleCelContent()
        let second = try XCTUnwrap(scratch.renderedCelContent)
        let secondBytes = try XCTUnwrap(RasterVectorParity.premultipliedBytes(of: second.image,
                                                                             size: second.window.size))
        let posedInkPixel = pixel(secondBytes, window: second.window, x: 140, y: 100)
        XCTAssertGreaterThan(posedInkPixel[1], posedInkPixel[0],
                             "Editable ink follows its independent horizontal pose")
        XCTAssertEqual(RasterVectorParity.premultipliedBytes(of: first.image, size: first.window.size), firstBytes,
                       "Advancing the source leaves the earlier rendered window immutable")
        XCTAssertEqual(heldBytes, firstBytes, "The pending-lift picture retains those original pixels")
        XCTAssertEqual(scratch.windowPixelCount, 0,
                       "Native replacement and held capture allocate no raster scratch")
    }

    /// A scattering eraser is a distinct retained element and punches without deleting paint.
    /// Its field ownership is checked through the live consumer and saved display list above.
    func testAScatteringEraserPunchIsANewStrokeRatherThanTheGesture() throws {
        var scattering = TestBrushes.hardRound
        scattering.dab.scatterAcross = 0.5
        scattering.dab.scatterAlong = 0.5
        let scene = scenario(brush: TestBrushes.hardRound, eraserBrush: scattering)
        let (canvas, _, _) = try erased(scene)
        let punches = strokes(canvas, .erase)
        XCTAssertEqual(punches.count, 1, "A scattering eraser still punches")
        XCTAssertNotEqual(punches.first?.id, Self.eraserID,
                          "The punch is its own display-list element while keeping the gesture's field")
        XCTAssertEqual(strokes(canvas, .paint).count, 1, "…and it must not delete")
    }

    // MARK: - 5. Display-list ordering, now that erase punches interleave

    /// `VectorCanvas`'s `strokes`/`fills`/`images` setters splice: they remove every element of that
    /// kind and reinsert the new list where the *first* removed one sat. That round-trips exactly
    /// only while each kind occupies one contiguous run — and the accessors' own comment flagged
    /// interleaving as the thing that would break it. An `.erase` element appended after paint
    /// strokes is exactly that interleaving, so this checks it.
    ///
    /// It does not break here, but **the reason it used to be safe is gone and the splice was changed
    /// to match.** The old argument was that every insertion goes through `insertionIndex(forKind:)`,
    /// so the list is kind-sorted as an invariant and each kind is one contiguous run. `addFill` now
    /// appends instead (LASSO_FILL.md §2a — a fill covers what is already on the layer), so a canvas
    /// the artist has filled *is* interleaved. `splicing` is therefore positional: it replaces the
    /// i-th element of a kind where that element already sits, which is the identity for any
    /// arrangement rather than only for a contiguous one. This scene builds its backdrop fill
    /// directly, so it is still the contiguous case — kept because a punch is the original
    /// interleaving that made the question worth asking. The last caller that leaned on the
    /// contiguity, the shape bake's `registerVectorStrokeUndo`, is gone: it swaps the whole element
    /// array through `registerVectorElementsUndo` now, which has nothing to reconstruct.
    func testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip() throws {
        let scene = scenario(brush: TestBrushes.hardRound,
                             backdrop: .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                             CGRect(x: 20, y: 20, width: 88, height: 88)))
        let (canvas, _, changed) = try erased(scene)
        XCTAssertTrue(changed, "Setup: the gesture should have retained a punch over the fill")

        let kinds = canvas.elements.map { element -> Int in
            if element.fill != nil { return 0 }
            if element.image != nil { return 1 }
            return 2
        }
        XCTAssertEqual(kinds, kinds.sorted(),
                       "The display list must stay sorted by kind — a punch appended out of that "
                       + "order would split the stroke run in two and make the splice lossy")
        XCTAssertEqual(canvas.elements.last?.stroke?.composite, .erase,
                       "Setup: the punch should be the last element")

        // Exactly what the two registerVector*Undo paths do: snapshot through the kind accessor,
        // then assign the snapshot straight back.
        let before = canvas.elements
        canvas.strokes = canvas.strokes
        canvas.fills = canvas.fills
        XCTAssertEqual(canvas.elements.map(\.id), before.map(\.id),
                       "A get→set round trip through the kind accessors must be the identity, "
                       + "punch included — otherwise every shape or fill undo reshuffles z-order")
    }

    /// **The ordering question this file used to record as open, settled.** The assertion here was
    /// its opposite: the list could not express a fill above a stroke, so a fill made after an erase
    /// gesture was inserted beneath that gesture and eaten by it, and the comment asked whoever
    /// settled it to change this deliberately. The owner settled it on 2026-08-21 — *"Cover
    /// everything"*, LASSO_FILL.md §2a — so `addFill` appends and drawing order is what the artist
    /// gets: the fill lands on top of the punch and the hole is painted back in.
    func testAFillAddedAfterAnErasePunchLandsOnTopOfIt() throws {
        let scene = scenario(brush: TestBrushes.hardRound)
        let (canvas, _, _) = try erased(scene)
        XCTAssertEqual(canvas.elements.last?.stroke?.composite, .erase, "Setup: a punch is on top")

        canvas.addFill(path: CGPath(rect: CGRect(origin: .zero, size: scene.canvasSize),
                                               transform: nil),
                       color: CodableColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))

        XCTAssertNotNil(canvas.elements.last?.fill,
                        "addFill appends, so a fill drawn after an erase goes above it — drawing "
                        + "order, which is what the artist expects and what they ruled for")
        XCTAssertNil(canvas.elements.first?.fill, "…and it did not land at the bottom of the list")

        guard let bytes = RasterVectorParity.premultipliedBytes(of: (try XCTUnwrap(canvas.render())), size: Self.canvasSize) else {
            return XCTFail("Could not read back the render")
        }
        let underTheGesture = (64 * Int(Self.canvasSize.width) + 64) * 4 + 3
        XCTAssertEqual(bytes[underTheGesture], 255,
                       "…so the punched hole is filled in rather than showing through the new fill")
    }
}
