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
    private func erased(_ scenario: ParityScenario) -> (canvas: VectorCanvas, backdrop: VectorElement?,
                                                        changed: Bool) {
        let backdrop = RasterVectorParity.backdropElement(scenario)
        let elements = (backdrop.map { [$0] } ?? []) + [.stroke(RasterVectorParity.paintStroke(scenario))]
        let canvas = VectorCanvas(size: scenario.canvasSize, elements: elements)
        let changed = canvas.erase(alongPath: scenario.eraserSamples, brush: scenario.eraserBrush,
                                   size: scenario.eraserSize, opacity: scenario.eraserOpacity,
                                   mode: .erase)
        return (canvas, backdrop, changed)
    }

    /// The hybrid's render against the raster ground truth for the same scene.
    ///
    /// The ground truth matches the parity tests: stamp the paint stroke whole, then stamp the eraser
    /// gesture whole with `isEraser: true`. The vector side is whatever `eraseHybrid` decided to
    /// leave in the display list — the stroke plus a punch, a punch alone, or nothing at all.
    ///
    /// The punch mints a fresh `id`, so it seeds a different dab RNG than the eraser stroke the raster
    /// tier stamped. That is invisible only while the eraser brush has `scatter == 0` and
    /// `rotationJitter == 0` — `BrushStamper.stampDab` consumes the RNG nowhere else for a round
    /// shape — which is true of every brush this file compares. A scattering *eraser* is gated out of
    /// deletion by `supportsCleanCut` but still produces a punch, and comparing one here would
    /// measure the seed rather than the eraser; `testAScatteringEraserIsNotComparedBySeed` pins that
    /// this restriction is understood rather than forgotten.
    private func parityOfHybrid(_ scenario: ParityScenario) -> ParityReport? {
        let (canvas, backdrop, _) = erased(scenario)
        let texture = RasterVectorParity.rasterBase(scenario, backdrop: backdrop)
        RasterVectorParity.stamp(RasterVectorParity.paintStroke(scenario), into: texture, isEraser: false)
        RasterVectorParity.stamp(RasterVectorParity.eraseStroke(scenario), into: texture, isEraser: true)
        return RasterVectorParity.report(raster: texture.renderToUIImage(), vector: canvas.render(),
                                         size: scenario.canvasSize)
    }

    private func strokes(_ canvas: VectorCanvas, _ composite: StrokeComposite) -> [VectorStroke] {
        canvas.elements.compactMap(\.stroke).filter { $0.composite == composite }
    }

    // MARK: - 1. Exactness — the claim the whole design rests on

    private static let brushes = [BrushLibrary.hardRound, BrushLibrary.softRound]
    private static let eraserOpacities: [Double] = [1, 0.4]

    private func assertHybridMatchesRaster(over backdropName: String, _ backdrop: ParityScenario.Backdrop,
                                           file: StaticString = #filePath, line: UInt = #line) {
        for brush in Self.brushes {
            for eraserOpacity in Self.eraserOpacities {
                for gesture in Gesture.allCases {
                    let name = "\(brush.name) / eraser opacity \(eraserOpacity) / \(gesture.label) / \(backdropName)"
                    let scene = scenario(brush: brush, eraserOpacity: eraserOpacity,
                                         gesture: gesture, backdrop: backdrop, name: name)
                    XCTContext.runActivity(named: name) { _ in
                        guard let report = parityOfHybrid(scene) else {
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

    func testHybridEraseOverABareStrokeIsPixelIdenticalToRasterErasing() {
        assertHybridMatchesRaster(over: "bare stroke", .none)
    }

    func testHybridEraseOverAVectorFillIsPixelIdenticalToRasterErasing() {
        assertHybridMatchesRaster(over: "over a fill",
                                  .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                        CGRect(x: 8, y: 40, width: 112, height: 48)))
    }

    func testHybridEraseOverAPlacedImageIsPixelIdenticalToRasterErasing() {
        assertHybridMatchesRaster(over: "over a placed image",
                                  .image(UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1),
                                         CGSize(width: 64, height: 64)))
    }

    /// The matrix above compares two renders and passes when they agree, so it would also pass if
    /// `erase` had done nothing and the raster tier's eraser had missed. Both are pinned here.
    func testTheMatrixIsNotVacuous() {
        for gesture in Gesture.allCases {
            let scene = scenario(brush: BrushLibrary.hardRound, gesture: gesture)
            let (canvas, _, changed) = erased(scene)
            XCTAssertTrue(changed, "\(gesture.label) should report a change")

            let before = VectorCanvas(size: scene.canvasSize,
                                      elements: [.stroke(RasterVectorParity.paintStroke(scene))]).render()
            guard let report = RasterVectorParity.report(raster: before, vector: canvas.render(),
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
    func testAGestureCoveringAStrokeEndToEndDeletesIt() {
        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: along,
                             backdrop: .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                             CGRect(x: 8, y: 40, width: 112, height: 48)))
        let (canvas, _, changed) = erased(scene)
        XCTAssertTrue(changed)
        XCTAssertEqual(strokes(canvas, .paint).count, 0, "The covered stroke should be gone outright")
        XCTAssertEqual(strokes(canvas, .erase).count, 1,
                       "The fill beneath still needs the punch, or the hole in it reappears")
        guard let report = parityOfHybrid(scene) else { return XCTFail("Could not read back both tiers") }
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
    func testPartialCoverageSplitsOrPunchesButNeverDeletes() {
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
            ("a square crossing", 2, scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                                              eraserSamples: across)),
            ("a partial-width shave", 1, scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                                                  eraserSamples: shave)),
            ("a nib narrower than the line", 1, scenario(brush: BrushLibrary.hardRound, eraserSize: 6,
                                                         eraserSamples: thin))
        ]

        for (name, expectedPieces, scene) in cases {
            XCTContext.runActivity(named: name) { _ in
                let (canvas, _, _) = erased(scene)
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
                guard let report = parityOfHybrid(scene) else {
                    return XCTFail("Could not read back both tiers for \(name)")
                }
                XCTAssertTrue(report.isExact, "\(name): \(report.diagnostic)")
            }
        }
    }

    /// `supportsCleanCut` gates deletion on the eraser being capable of removing ink outright. Each row
    /// is a distinct condition, run over the gesture that *would* delete, so a regression that drops one
    /// condition fails on that row alone.
    func testDeletionIsSkippedWhereverTheAlphaGateFails() {
        var scattering = BrushLibrary.hardRound
        scattering.scatter = 0.4
        var jittering = BrushLibrary.hardRound
        jittering.rotationJitter = 0.5
        var square = BrushLibrary.hardRound
        square.tip = .stamp(.builtIn(.square))
        var soft = BrushLibrary.hardRound
        soft.hardness = 0.5

        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        func rejected(_ eraserBrush: Brush? = nil, opacity: Double = 1) -> ParityScenario {
            scenario(brush: BrushLibrary.hardRound, eraserBrush: eraserBrush, eraserOpacity: opacity,
                     eraserSize: Self.wideNib, eraserSamples: along)
        }
        let cases: [(String, ParityScenario)] = [
            ("soft falloff", rejected(BrushLibrary.softRound)),
            ("hardness below the gate", rejected(soft)),
            ("partial opacity", rejected(opacity: 0.4)),
            ("scattering eraser", rejected(scattering)),
            ("rotation-jittering square eraser", rejected(jittering)),
            ("square eraser", rejected(square))
        ]

        for (name, scene) in cases {
            XCTContext.runActivity(named: name) { _ in
                let (canvas, _, _) = erased(scene)
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
    /// beside the hardness/opacity/dynamics/scatter gates above — and the shipped `BrushLibrary.pencil`
    /// preset had grain enabled, so a pencil-*shaped* eraser could never take the clean-cut path no
    /// matter how hard, opaque or steady it was tuned. There is no `grain` field left to check, so that
    /// extra veto is simply gone: the Pencil preset is judged on exactly the same four gates as Soft
    /// Round, Hard Round and Pen, with nothing held against it. Since §12 stage 5 all four are one
    /// `BrushTip.round` and there is not even a shape left to hold against it.
    ///
    /// `BrushLibrary.pencil`'s own hardness (0.7) still fails the unrelated hardness gate on its own, so
    /// this pins the shape in isolation against a brush tuned to clear every *other* gate — the only way
    /// to isolate what the grain veto used to cost it, now that grain cannot be toggled to show the
    /// same brush passing and failing.
    func testAHardOpaquePencilShapedEraserCleanCutsWhereGrainUsedToVetoIt() {
        var pencilEraser = BrushLibrary.pencil
        pencilEraser.hardness = 1
        XCTAssertTrue(BrushLibrary.isPencilPreset(pencilEraser),
                      "Setup: still the preset the grain veto used to single out")

        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: BrushLibrary.hardRound, eraserBrush: pencilEraser, eraserSize: Self.wideNib,
                             eraserSamples: along,
                             backdrop: .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                             CGRect(x: 8, y: 40, width: 112, height: 48)))
        let (canvas, _, changed) = erased(scene)
        XCTAssertTrue(changed)
        XCTAssertEqual(strokes(canvas, .paint).count, 0,
                       "A hard, opaque, steady pencil-shaped eraser now deletes what it fully covers")
        XCTAssertEqual(strokes(canvas, .erase).count, 1,
                       "The fill beneath still needs the punch, or the hole in it reappears")
        guard let report = parityOfHybrid(scene) else { return XCTFail("Could not read back both tiers") }
        XCTAssertTrue(report.isExact, "Deleting a covered stroke must not move a pixel: \(report.diagnostic)")
    }

    /// The other half of the gate. A *paint* stroke that scatters throws dabs off its own centreline,
    /// so the capsule chain the coverage test measures against does not bound its ink and "covered" is
    /// a claim about the wrong shape. Such a stroke is never deleted, only punched.
    func testAScatteringPaintStrokeIsNeverDeleted() {
        var scattering = BrushLibrary.hardRound
        scattering.scatter = 0.5
        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: scattering, eraserBrush: BrushLibrary.hardRound,
                             eraserSize: Self.wideNib, eraserSamples: along)
        let (canvas, _, _) = erased(scene)
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
    func testTheSplitIsExactOnlyBecauseThePiecesShareTheParentsLattice() {
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib)
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

        let whole = VectorCanvas(size: scene.canvasSize,
                                 elements: [.stroke(paint), .stroke(erase)]).render()
        guard let naiveReport = RasterVectorParity.report(
                raster: whole,
                vector: VectorCanvas(size: scene.canvasSize, elements: naive + [.stroke(erase)]).render(),
                size: scene.canvasSize),
              let sharedReport = RasterVectorParity.report(
                raster: whole,
                vector: VectorCanvas(size: scene.canvasSize, elements: shared + [.stroke(erase)]).render(),
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
    func testCuttingAPieceAgainStaysOnTheOriginalLattice() {
        // First gesture: squarely across the middle at x = 64, which splits the line in two.
        let first = Self.ramp(from: CGPoint(x: 64, y: 24), to: CGPoint(x: 64, y: 104), count: 9,
                              from: 1, to: 1)
        // Second: across the left-hand piece at x = 40.
        let second = Self.ramp(from: CGPoint(x: 40, y: 24), to: CGPoint(x: 40, y: 104), count: 9,
                               from: 1, to: 1)
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: first)
        let paint = RasterVectorParity.paintStroke(scene)
        let canvas = VectorCanvas(size: scene.canvasSize, elements: [.stroke(paint)])
        canvas.erase(alongPath: first, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase)
        XCTAssertEqual(strokes(canvas, .paint).count, 2, "The first gesture should have split the line")
        canvas.erase(alongPath: second, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase)

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
        let texture = RasterVectorParity.rasterBase(scene, backdrop: nil)
        RasterVectorParity.stamp(paint, into: texture, isEraser: false)
        for gesture in [first, second] {
            var punch = RasterVectorParity.eraseStroke(scene)
            punch.samples = gesture
            RasterVectorParity.stamp(punch, into: texture, isEraser: true)
        }
        guard let report = RasterVectorParity.report(raster: texture.renderToUIImage(),
                                                     vector: canvas.render(),
                                                     size: scene.canvasSize) else {
            return XCTFail("Could not read back both tiers")
        }
        XCTAssertTrue(report.isExact, "Two erases must still be raster-exact: \(report.diagnostic)")
    }

    /// Deletion, by contrast, *is* exact — the property that lets Mode 1 keep it. Same shape of
    /// comparison as above, with the whole stroke removed instead of cut.
    func testDeletingAFullyCoveredStrokeIsExact() {
        let along = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 120, y: 64), count: 15,
                              from: 1, to: 1)
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
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
            raster: VectorCanvas(size: scene.canvasSize,
                                 elements: [.stroke(paint), .stroke(erase)]).render(),
            vector: VectorCanvas(size: scene.canvasSize, elements: [.stroke(erase)]).render(),
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
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib)
        let paint = RasterVectorParity.paintStroke(scene)
        // Stops at x = 88. The nib's own radius-24 cap still reaches x = 112, so every *cross-section*
        // of the stroke (whose samples end at x = 104) is covered — but the stroke's ink runs to
        // x = 116 in its end cap, and that is outside. Isolating the cap check from the cross-section
        // check is the whole point: stopping any nearer and the nib swallows the cap too, which is what
        // this test originally did and why it did not test anything.
        let short = Self.ramp(from: CGPoint(x: 8, y: 64), to: CGPoint(x: 88, y: 64), count: 13,
                              from: 1, to: 1)
        guard let sweep = VectorEraser.Sweep(samples: short, brush: BrushLibrary.hardRound,
                                             size: Self.wideNib) else {
            return XCTFail("The eraser gesture should have a footprint")
        }
        let erasers = VectorEraser.cleanCutCapsules(sweep.capsules, brush: BrushLibrary.hardRound,
                                                    size: Self.wideNib)
        XCTAssertFalse(VectorEraser.isEntirelyCovered(paint.samples, brush: paint.brush, size: paint.size,
                                                      by: erasers, sweep: sweep),
                       "The trailing cap is outside the eraser, so the stroke is not entirely covered")

        let canvas = VectorCanvas(size: scene.canvasSize, elements: [.stroke(paint)])
        canvas.erase(alongPath: short, brush: BrushLibrary.hardRound, size: Self.wideNib,
                     opacity: 1, mode: .erase)
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
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSamples: drag)
        var second = RasterVectorParity.paintStroke(scene)
        second.id = UUID()
        second.samples = Self.ramp(from: CGPoint(x: 24, y: 112), to: CGPoint(x: 104, y: 112),
                                   count: 9, from: 1, to: 1)

        let canvas = VectorCanvas(size: scene.canvasSize,
                                  elements: [.stroke(RasterVectorParity.paintStroke(scene)),
                                             .stroke(second)])
        canvas.erase(alongPath: drag, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase)

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
    func testErasingAStrokeAwayCompletelyLeavesAnEmptyDisplayList() {
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                             eraserSamples: Self.ramp(from: CGPoint(x: 8, y: 64),
                                                      to: CGPoint(x: 120, y: 64),
                                                      count: 15, from: 1, to: 1))
        let (canvas, _, changed) = erased(scene)
        XCTAssertTrue(changed)
        XCTAssertEqual(canvas.elements.count, 0,
                       "A fully resolved erase must retain nothing at all, or Mode 1 grows the list forever")

        // And the layer really is blank, not merely element-free by accident.
        guard let bytes = RasterVectorParity.premultipliedBytes(of: canvas.render(), size: scene.canvasSize) else {
            return XCTFail("Could not read back the render")
        }
        XCTAssertFalse(bytes.contains { $0 != 0 }, "The rendered layer should be fully transparent")
    }

    /// GC's second case: a punch whose backdrop is deleted later. It survives until the next erase —
    /// documented behaviour, since it renders as a hole in nothing — and is collected then.
    func testAPunchIsCollectedOnceItsBackdropIsDeleted() {
        let scene = scenario(brush: BrushLibrary.hardRound)
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
                     opacity: 1, mode: .erase)
        XCTAssertEqual(strokes(canvas, .erase).count, 1, "The first erase should retain a punch")

        // Delete everything the punch was over, leaving it stranded.
        canvas.elements = canvas.elements.filter { $0.stroke?.composite == .erase || $0.stroke?.id == bystander.id }
        canvas.bumpVersion()
        XCTAssertEqual(strokes(canvas, .erase).count, 1, "GC runs on commit, not per frame")

        // Any later erase collects it — here, one over the bystander down the left edge.
        canvas.erase(alongPath: Self.ramp(from: CGPoint(x: 8, y: 96), to: CGPoint(x: 8, y: 124),
                                          count: 5, from: 1, to: 1),
                     brush: scene.eraserBrush, size: scene.eraserSize, opacity: 1, mode: .erase)
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
    /// the `maxPaintReach() == 0` path in `hasContentBeneath`, which is correct only because the fill
    /// check runs before it.
    func testModeOneErasesAFillOnALayerWithNoStrokesAtAll() {
        let rect = CGRect(x: 8, y: 40, width: 112, height: 48)
        let fill = VectorFillElement(path: CGPath(rect: rect, transform: nil),
                                     color: CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.fill(fill)])
        let gesture = Gesture.squareCut.samples
        XCTAssertTrue(canvas.erase(alongPath: gesture, brush: BrushLibrary.hardRound, size: 16,
                                   opacity: 1, mode: .erase),
                      "Mode 1 has work to do on a strokeless layer")
        XCTAssertEqual(canvas.elements.filter { $0.stroke?.composite == .erase }.count, 1)

        guard let bytes = RasterVectorParity.premultipliedBytes(of: canvas.render(), size: Self.canvasSize) else {
            return XCTFail("Could not read back the render")
        }
        // Under the gesture, inside the fill.
        let hole = (64 * Int(Self.canvasSize.width) + 64) * 4 + 3
        XCTAssertEqual(bytes[hole], 0, "The punch should go straight through the fill")
    }

    /// A gesture that never reaches anything must leave the list exactly as it was — no punch, and no
    /// spurious `changed` that would push an empty undo entry.
    func testAnEraseOverEmptySpaceChangesNothing() {
        let scene = scenario(brush: BrushLibrary.hardRound,
                             eraserSamples: Self.ramp(from: CGPoint(x: 8, y: 8), to: CGPoint(x: 120, y: 8),
                                                      count: 9, from: 1, to: 1))
        let (canvas, _, changed) = erased(scene)
        XCTAssertFalse(changed, "Nothing was under the gesture, so nothing changed")
        XCTAssertEqual(canvas.elements.count, 1)
        XCTAssertEqual(strokes(canvas, .erase).count, 0, "A punch over nothing must not be retained")
    }

    /// What re-erasing the same place actually costs, pinned rather than wished away.
    ///
    /// `hasContentBeneath` asks about stroke *geometry*, not about ink still visible after earlier
    /// punches, so a second gesture over a stroke the eraser does not wholly cover retains a second punch. That is the
    /// design being consistent rather than leaking: an eraser **is** a stroke, and N eraser gestures
    /// cost N elements exactly as N paint gestures do. What
    /// `testErasingAStrokeAwayCompletelyLeavesAnEmptyDisplayList` covers is that an erase which
    /// fully resolves costs *nothing*, not that repeated scrubbing is free.
    ///
    /// So this pins the two properties that do hold: growth is one element per gesture (not one per
    /// stretch of backdrop, which is what the trimmed version produced), and stacking stays exact.
    func testReErasingTheSamePlaceCostsOneElementPerGestureAndStaysExact() {
        let scene = scenario(brush: BrushLibrary.hardRound)
        let (canvas, _, _) = erased(scene)
        XCTAssertEqual(strokes(canvas, .erase).count, 1)

        canvas.erase(alongPath: scene.eraserSamples, brush: scene.eraserBrush, size: scene.eraserSize,
                     opacity: 1, mode: .erase)
        XCTAssertEqual(strokes(canvas, .erase).count, 2,
                       "One gesture, one element — and never more than one")

        // Two identical full-opacity punches remove exactly what one does, so the render is still the
        // raster ground truth for a single erase.
        let texture = RasterVectorParity.rasterBase(scene, backdrop: nil)
        RasterVectorParity.stamp(RasterVectorParity.paintStroke(scene), into: texture, isEraser: false)
        RasterVectorParity.stamp(RasterVectorParity.eraseStroke(scene), into: texture, isEraser: true)
        guard let report = RasterVectorParity.report(raster: texture.renderToUIImage(),
                                                     vector: canvas.render(),
                                                     size: scene.canvasSize) else {
            return XCTFail("Could not read back both tiers")
        }
        XCTAssertTrue(report.isExact, "Stacked punches must still be exact: \(report.diagnostic)")
    }

    /// The restriction `parityOfHybrid` documents, made explicit: a scattering eraser is admitted as a
    /// punch (it is only barred from *splitting*), and the punch is a **new stroke** with an id and a
    /// random field of its own rather than the gesture's. Pinning the behaviour here is what stops
    /// someone later "fixing" the parity gap by comparing a scattering eraser and concluding the
    /// hybrid is broken.
    func testAScatteringEraserPunchIsANewStrokeRatherThanTheGesture() {
        var scattering = BrushLibrary.hardRound
        scattering.scatter = 0.5
        let scene = scenario(brush: BrushLibrary.hardRound, eraserBrush: scattering)
        let (canvas, _, _) = erased(scene)
        let punches = strokes(canvas, .erase)
        XCTAssertEqual(punches.count, 1, "A scattering eraser still punches")
        XCTAssertNotEqual(punches.first?.id, Self.eraserID,
                          "The punch is its own stroke, with its own random field, so its dab scatter cannot be compared against a raster tier drawing from the gesture's")
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
    /// directly, so it is still the contiguous case — kept because it is what
    /// `CanvasManager+Shape.registerVectorStrokeUndo` relies on, and because a punch is the original
    /// interleaving that made the question worth asking.
    func testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip() {
        let scene = scenario(brush: BrushLibrary.hardRound,
                             backdrop: .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                                             CGRect(x: 20, y: 20, width: 88, height: 88)))
        let (canvas, _, changed) = erased(scene)
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
    func testAFillAddedAfterAnErasePunchLandsOnTopOfIt() {
        let scene = scenario(brush: BrushLibrary.hardRound)
        let (canvas, _, _) = erased(scene)
        XCTAssertEqual(canvas.elements.last?.stroke?.composite, .erase, "Setup: a punch is on top")

        canvas.addFill(canvasSpacePath: CGPath(rect: CGRect(origin: .zero, size: scene.canvasSize),
                                               transform: nil),
                       color: CodableColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))

        XCTAssertNotNil(canvas.elements.last?.fill,
                        "addFill appends, so a fill drawn after an erase goes above it — drawing "
                        + "order, which is what the artist expects and what they ruled for")
        XCTAssertNil(canvas.elements.first?.fill, "…and it did not land at the bottom of the list")

        guard let bytes = RasterVectorParity.premultipliedBytes(of: canvas.render(), size: Self.canvasSize) else {
            return XCTFail("Could not read back the render")
        }
        let underTheGesture = (64 * Int(Self.canvasSize.width) + 64) * 4 + 3
        XCTAssertEqual(bytes[underTheGesture], 255,
                       "…so the punched hole is filled in rather than showing through the new fill")
    }
}
