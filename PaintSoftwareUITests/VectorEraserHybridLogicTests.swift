import XCTest
import UIKit
import CoreGraphics

/// `VECTOR_ERASER_PLAN.md` §1's Mode 1 commit — `VectorCanvas.eraseHybrid` — under test.
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
///    the result is byte-identical to the raster ground truth, over the same §8 matrix, at tolerance
///    zero. This is the design's whole justification and the one test that can falsify it.
/// 2. **Whole-stroke deletion** fires where the eraser covers a stroke completely, and nowhere else.
/// 3. **No partial split**, plus the divergence that is the reason for it — so that anyone re-wiring
///    `conservativeCuts` finds out immediately rather than from a bug report about shifted stroke tips.
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
    private static let eraserID = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!

    private static func ramp(from start: CGPoint, to end: CGPoint, count: Int,
                             from p0: CGFloat, to p1: CGFloat) -> [VectorSample] {
        (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            return VectorSample(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t,
                                pressure: p0 + (p1 - p0) * t)
        }
    }

    /// The line under the eraser: ink spans y ∈ [52, 76] at full pressure.
    private static let paintSamples = ramp(from: CGPoint(x: 24, y: 64), to: CGPoint(x: 104, y: 64),
                                           count: 9, from: 0.45, to: 1)

    private enum Gesture: String, CaseIterable {
        /// Straight across the line.
        case squareCut
        /// Across at 45°, so both cut boundaries land between samples.
        case diagonalCut
        /// Along the line, shaving its top edge — partial-width coverage, which only a punch can express.
        case edgeShave

        var samples: [VectorSample] {
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
                          eraserSamples: [VectorSample]? = nil,
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
    /// The ground truth is unchanged from §8's: stamp the paint stroke whole, then stamp the eraser
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
    /// than grazing. The §8 matrix deliberately uses 16 — the awkward size — so tests about coverage
    /// need their own.
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

    /// Partial coverage never deletes, however inviting it looks. Each row is a different way of being
    /// partial, and each must leave the stroke whole, keeping its id — and therefore its dab seed.
    func testPartialCoverageNeverDeletesTheStroke() {
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

        let cases: [(String, ParityScenario)] = [
            ("a square crossing", scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                                           eraserSamples: across)),
            ("a partial-width shave", scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib,
                                               eraserSamples: shave)),
            ("a nib narrower than the line", scenario(brush: BrushLibrary.hardRound, eraserSize: 6,
                                                      eraserSamples: thin))
        ]

        for (name, scene) in cases {
            XCTContext.runActivity(named: name) { _ in
                let (canvas, _, _) = erased(scene)
                XCTAssertEqual(strokes(canvas, .paint).count, 1, "\(name) must leave the stroke whole")
                XCTAssertEqual(strokes(canvas, .paint).first?.id, Self.paintID,
                               "\(name) changed nothing about the stroke, so it must keep its id and dab seed")
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
        square.shape = .square
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

    // MARK: - 3. Why there is no partial split

    /// The measurement that unwired the split, kept as a test so re-wiring it fails loudly.
    ///
    /// Cut the stroke at the span `conservativeCuts` says is safe — the most favourable case there is,
    /// a hard round eraser at full opacity crossing squarely — and compare the pieces plus the punch
    /// against the whole stroke plus the same punch. The design's original claim was that these are
    /// identical. They are not, and the reason is not the cut: a surviving piece is re-stamped as a new
    /// stroke, so `BrushStamper` re-anchors its dab lattice and its pressure ramp at the piece's first
    /// sample and its ink lands somewhere new along its whole length — including the far tip, which is
    /// the part of it the punch cannot cover.
    ///
    /// Fixing that means anchoring the lattice to arclength from the stroke's origin, or giving
    /// `VectorStroke` a parametric visible range so a piece reuses the original lattice. Until one of
    /// those exists, this test should keep failing for anyone who reconnects `conservativeCuts` to
    /// `VectorCanvas.eraseHybrid`.
    func testAPartialSplitDivergesOutsideThePunchWhichIsWhyItIsNotWired() {
        let scene = scenario(brush: BrushLibrary.hardRound, eraserSize: Self.wideNib)
        let paint = RasterVectorParity.paintStroke(scene)
        let erase = RasterVectorParity.eraseStroke(scene)
        guard let sweep = VectorEraser.Sweep(samples: erase.samples, brush: erase.brush,
                                             size: erase.size, mode: .erase) else {
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

        let pieces: [VectorElement] = StrokeGeometry.splitStroke(paint.samples, removing: cuts).map { run in
            var piece = paint
            piece.id = UUID()
            piece.samples = run
            return .stroke(piece)
        }
        XCTAssertEqual(pieces.count, 2, "A square crossing should yield two pieces")

        guard let report = RasterVectorParity.report(
            raster: VectorCanvas(size: scene.canvasSize,
                                 elements: [.stroke(paint), .stroke(erase)]).render(),
            vector: VectorCanvas(size: scene.canvasSize, elements: pieces + [.stroke(erase)]).render(),
            size: scene.canvasSize) else {
            return XCTFail("Could not read back the two renders")
        }
        XCTAssertFalse(report.isExact,
                       "If a conservatively inset split has become pixel-exact, the stamper's lattice anchoring must have changed — re-read VectorEraser's Mode 1 notes and consider re-wiring the split. Measured: \(report.diagnostic)")
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
                                             size: erase.size, mode: .erase) else {
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
                                             size: Self.wideNib, mode: .erase) else {
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

    /// The common case §1 wanted to cost nothing: scribble a stroke out completely and the layer ends
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
    /// cost N elements exactly as N paint gestures do. What §1 asked for — and what
    /// `testErasingAStrokeAwayCompletelyLeavesAnEmptyDisplayList` covers — is that an erase which
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

    /// The seed restriction `parityOfHybrid` documents, made explicit: a scattering eraser is admitted
    /// as a punch (it is only barred from *splitting*), and its punch mints a fresh id. Pinning the
    /// split behaviour here is what stops someone later "fixing" the parity gap by comparing a
    /// scattering eraser and concluding the hybrid is broken.
    func testAScatteringEraserIsNotComparedBySeed() {
        var scattering = BrushLibrary.hardRound
        scattering.scatter = 0.5
        let scene = scenario(brush: BrushLibrary.hardRound, eraserBrush: scattering)
        let (canvas, _, _) = erased(scene)
        let punches = strokes(canvas, .erase)
        XCTAssertEqual(punches.count, 1, "A scattering eraser still punches")
        XCTAssertNotEqual(punches.first?.id, Self.eraserID,
                          "The punch mints its own id, so its dab scatter cannot be compared against a raster tier seeded from the gesture")
        XCTAssertEqual(strokes(canvas, .paint).count, 1, "…and it must not delete")
    }
}
