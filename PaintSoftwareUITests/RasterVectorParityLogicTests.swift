import XCTest
import UIKit
import CoreGraphics

/// One pixel's premultiplied RGBA bytes, carried in a `ParityReport` purely so a failure can name
/// the two values that disagreed rather than only the size of the disagreement.
struct ParityPixel: Equatable, CustomStringConvertible {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    init(_ bytes: [UInt8], pixelIndex: Int) {
        let i = pixelIndex * 4
        r = bytes[i]; g = bytes[i + 1]; b = bytes[i + 2]; a = bytes[i + 3]
    }

    var description: String { "rgba(\(r), \(g), \(b), \(a))" }
}

/// The result of comparing two renders of the same scene, one per tier.
///
/// Every field exists to make a failure *actionable*. "Not equal" is useless here: the interesting
/// question is always whether a mismatch is a handful of anti-aliased edge pixels off by one LSB
/// (a rounding difference between two contexts) or a whole region at delta 255 (a punch that
/// reached different content), and those two look identical to `XCTAssertEqual`.
struct ParityReport {
    /// Worst single-channel absolute difference anywhere on the canvas, 0...255.
    var maxChannelDelta: Int
    /// Pixels where *any* channel differs by more than the comparison's tolerance.
    var differingPixelCount: Int
    var totalPixelCount: Int
    /// Mean absolute channel difference over every channel of every pixel — the number that
    /// separates "one bad pixel" from "the whole image is off by a hair".
    var meanChannelDelta: Double
    /// Where `maxChannelDelta` occurred, in canvas point space (top-left origin).
    var worstPixel: CGPoint?
    var worstRaster: ParityPixel?
    var worstVector: ParityPixel?

    var isExact: Bool { maxChannelDelta == 0 }

    var diagnostic: String {
        var text = "max channel delta \(maxChannelDelta)/255, "
            + "\(differingPixelCount)/\(totalPixelCount) pixels differ, "
            + String(format: "mean channel delta %.5f", meanChannelDelta)
        if let worstPixel, let worstRaster, let worstVector {
            text += "; worst at (\(Int(worstPixel.x)), \(Int(worstPixel.y))): "
                + "raster \(worstRaster) vs vector \(worstVector)"
        }
        return text
    }
}

/// One "draw a stroke, erase it" scene, expressed once and rendered by both tiers.
///
/// A single description drives both renders precisely because the two tiers *must* be handed
/// identical brushes, sizes, opacities, samples and dab seeds. Any of those diverging silently turns
/// the whole comparison into a measurement of something else — the mismatch would be real and the
/// conclusion drawn from it would be wrong.
struct ParityScenario {
    enum Backdrop {
        /// Nothing beneath the paint stroke — the purest measurement of the punch itself.
        case none
        /// A `VectorFillElement` covering `rect`.
        case fill(CodableColor, CGRect)
        /// A `VectorImageElement`: a solid `UIColor` square of `size`, placed at the canvas centre.
        case image(UIColor, CGSize)
    }

    var name: String
    var canvasSize: CGSize
    var brush: Brush
    var paintColor: CodableColor
    var paintSize: CGFloat
    var paintOpacity: Double
    var paintSamples: StrokeSamples
    var eraserBrush: Brush
    var eraserColor: CodableColor
    var eraserSize: CGFloat
    var eraserOpacity: Double
    var eraserSamples: StrokeSamples
    var backdrop: Backdrop
    /// Fixed rather than freshly generated, so a scatter/jitter-carrying brush replays to the same
    /// dabs on a rerun and a reported failure is reproducible. Both tiers draw their random field from
    /// these — `VectorStroke.seed` is minted fresh per stroke (BRUSH.md §4), so a scenario that wants
    /// two runs to agree has to name the field rather than let it be rolled.
    var paintID: UUID
    var eraserID: UUID
}

/// The raster-vs-vector comparison harness behind the hybrid eraser's acceptance test.
///
/// The hybrid design rests on one claim: that keeping the eraser as a retained `.erase` element in
/// the vector display list is *indistinguishable* from having erased the same stroke on a raster
/// layer. That is what lets the hybrid fall back to an alpha punch whenever a geometric split cannot
/// express the cut. The claim is checkable — both tiers rasterize through the same `BrushStamper`, so
/// the two results should agree byte for byte, not approximately — and this is what checks it.
///
/// Deliberately a plain namespace rather than test-case methods: `parityOfGeometricSplit` below is
/// meant to be *called* from other test files too, not just this one.
enum RasterVectorParity {

    // MARK: - Building the two tiers

    static func paintStroke(_ scenario: ParityScenario) -> VectorStroke {
        VectorStroke(id: scenario.paintID, brush: scenario.brush, color: scenario.paintColor,
                     size: scenario.paintSize, opacity: scenario.paintOpacity,
                     samples: scenario.paintSamples, composite: .paint,
                     seed: DabRandom.seed(for: scenario.paintID))
    }

    static func eraseStroke(_ scenario: ParityScenario) -> VectorStroke {
        VectorStroke(id: scenario.eraserID, brush: scenario.eraserBrush, color: scenario.eraserColor,
                     size: scenario.eraserSize, opacity: scenario.eraserOpacity,
                     samples: scenario.eraserSamples, composite: .erase,
                     seed: DabRandom.seed(for: scenario.eraserID))
    }

    static func backdropElement(_ scenario: ParityScenario) -> VectorElement? {
        switch scenario.backdrop {
        case .none:
            return nil
        case .fill(let color, let rect):
            return .fill(VectorFillElement(path: CGPath(rect: rect, transform: nil), color: color))
        case .image(let color, let size):
            let image = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
                color.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            let centre = CGPoint(x: scenario.canvasSize.width / 2, y: scenario.canvasSize.height / 2)
            return .image(VectorImageElement(image: image,
                                             transform: LayerTransform(position: centre, scale: 1, rotation: 0),
                                             fileName: nil))
        }
    }

    /// Mirrors `VectorCanvas.stamp(stroke:into:isEraser:)`, which is private to that class. The
    /// `random:` argument is the load-bearing part: the vector tier draws from the stroke's own field,
    /// so the raster tier has to as well or a brush with scatter or rotation jitter lands its dabs
    /// somewhere else entirely and the comparison measures the randomness instead of the eraser.
    static func stamp(_ stroke: VectorStroke, into target: DabTarget, isEraser: Bool) {
        let samples = stroke.samples
        BrushStamper.stampStroke(into: target, samples: samples, brush: stroke.brush,
                                 color: stroke.uiColor, brushSize: stroke.size,
                                 brushOpacity: stroke.opacity, isEraser: isEraser,
                                 random: stroke.dabRandom)
    }

    /// The raster tier's starting bitmap.
    ///
    /// The backdrop is rendered *by the vector renderer* and then loaded into the texture, rather
    /// than being redrawn with an equivalent set of Core Graphics calls. That is the only way to hold
    /// the backdrop constant across the two tiers, and holding it constant is what makes the reported
    /// delta attributable to the punch. Redrawing it independently would fold "does CG fill this path
    /// the same way in two different contexts" into the same number, which this harness is not meant
    /// to measure. The load is lossless: same size, scale 1, source-over onto a cleared context, so
    /// the bytes survive the transfer.
    ///
    /// Internal rather than private because `VectorEraserHybridLogicTests` builds the same ground
    /// truth against a display list it mutates through `VectorCanvas.erase` — it needs this half
    /// without the vector half `tiers(_:)` builds alongside it, and must share the *same* backdrop
    /// element.
    static func rasterBase(_ scenario: ParityScenario, backdrop: VectorElement?) -> RasterLayerTexture {
        guard let backdrop else { return RasterLayerTexture.empty(size: scenario.canvasSize) }
        let image = VectorCanvas(size: scenario.canvasSize, elements: [backdrop]).render()
        return RasterLayerTexture.load(from: image, size: scenario.canvasSize)
    }

    /// Both renders of one scenario.
    ///
    /// - Raster tier: backdrop, then the paint stroke stamped normally, then the eraser gesture
    ///   stamped `isEraser: true` — i.e. exactly what a raster layer does when a user erases.
    /// - Vector tier: the display list `[backdrop?, .stroke(paint), .stroke(erase)]`, where the erase
    ///   element punches `.destinationOut` against everything beneath it.
    static func tiers(_ scenario: ParityScenario) -> (raster: UIImage, vector: UIImage) {
        let paint = paintStroke(scenario)
        let erase = eraseStroke(scenario)
        // Built once and shared, so the placed image is literally the same `UIImage` in both tiers.
        let backdrop = backdropElement(scenario)

        let texture = rasterBase(scenario, backdrop: backdrop)
        stamp(paint, into: texture, isEraser: false)
        stamp(erase, into: texture, isEraser: true)

        let elements = (backdrop.map { [$0] } ?? []) + [.stroke(paint), .stroke(erase)]
        let vector = VectorCanvas(size: scenario.canvasSize, elements: elements).render()
        return (texture.renderToUIImage(), vector)
    }

    // MARK: - Comparison

    /// `image`'s pixels as premultiplied RGBA bytes, top-left origin.
    ///
    /// Drawn into a context built here rather than read out of `image.cgImage` directly: a `CGImage`
    /// can carry any bit layout, alpha position, row padding or colour space its producer chose, and
    /// the two tiers reach this point through different producers (`CGContext.makeImage()` for the
    /// raster texture, `UIGraphicsImageRenderer` for the vector canvas). Normalising both through one
    /// 8-bit `deviceRGB`/`premultipliedLast` context — the same pair `RasterLayerTexture` and
    /// `PixelOps` use everywhere else in the app — is what makes the byte comparison mean anything.
    ///
    /// The context is flipped the way `RasterLayerTexture.ensureContext()` flips its own, so
    /// `UIImage.draw` composites right side up and a reported pixel coordinate is in canvas point
    /// space rather than upside down.
    static func premultipliedBytes(of image: UIImage, size: CGSize) -> [UInt8]? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            UIGraphicsPopContext()
            return true
        }
        return ok ? bytes : nil
    }

    /// Compares two same-size renders channel by channel. `tolerance` only widens what counts toward
    /// `differingPixelCount`; `maxChannelDelta` is always the true worst case, so a test can tolerate
    /// noise without losing the ability to see how bad it got.
    static func report(raster: UIImage, vector: UIImage, size: CGSize, tolerance: Int = 0) -> ParityReport? {
        guard let a = premultipliedBytes(of: raster, size: size),
              let b = premultipliedBytes(of: vector, size: size),
              a.count == b.count, !a.isEmpty else { return nil }

        let width = Int(size.width.rounded())
        let pixelCount = a.count / 4
        var maxDelta = 0
        var worstIndex = -1
        var differing = 0
        var deltaSum: Int64 = 0

        for pixel in 0..<pixelCount {
            var worstChannel = 0
            for channel in 0..<4 {
                let delta = abs(Int(a[pixel * 4 + channel]) - Int(b[pixel * 4 + channel]))
                deltaSum += Int64(delta)
                if delta > worstChannel { worstChannel = delta }
            }
            if worstChannel > maxDelta {
                maxDelta = worstChannel
                worstIndex = pixel
            }
            if worstChannel > tolerance { differing += 1 }
        }

        var report = ParityReport(maxChannelDelta: maxDelta,
                                  differingPixelCount: differing,
                                  totalPixelCount: pixelCount,
                                  meanChannelDelta: Double(deltaSum) / Double(pixelCount * 4),
                                  worstPixel: nil, worstRaster: nil, worstVector: nil)
        if worstIndex >= 0 {
            report.worstPixel = CGPoint(x: worstIndex % width, y: worstIndex / width)
            report.worstRaster = ParityPixel(a, pixelIndex: worstIndex)
            report.worstVector = ParityPixel(b, pixelIndex: worstIndex)
        }
        return report
    }

    /// The acceptance measurement: retained-`.erase`-element vector result vs raster ground truth.
    static func parityOfRetainedPunch(_ scenario: ParityScenario, tolerance: Int = 0) -> ParityReport? {
        let (raster, vector) = tiers(scenario)
        return report(raster: raster, vector: vector, size: scenario.canvasSize, tolerance: tolerance)
    }

    // MARK: - The raw split's tuning hook

    /// **A measurement hook for the raw geometric split, deliberately unasserted.**
    ///
    /// `parityOfRetainedPunch` measures the alpha-punch half of the hybrid. This measures the
    /// *other* half: the paint stroke geometrically cut into surviving pieces, with no `.erase`
    /// element in the display list at all, against the same raster ground truth. That is the number
    /// a "clean cut" gate would need to be tuned against — a span may only be resolved geometrically
    /// when the split's own parity is good enough to be invisible, and the threshold varies with
    /// hardness/opacity.
    ///
    /// No assertion ships with it: the split is expected to be *bad* for a soft brush, for
    /// `eraserOpacity < 1`, and for anything grazing the stroke rather than crossing it, and that
    /// badness is the whole reason the punch fallback exists. What this provides is the instrument to
    /// assert `report.maxChannelDelta == 0` wherever a gate claims a cut is clean, and record the
    /// measured delta everywhere else.
    ///
    /// Two things it deliberately does *not* paper over:
    ///
    /// - A backdrop is never cut. A fill or a placed image beneath the stroke has no geometry the
    ///   eraser can trim, so any scenario with a backdrop can only ever be resolved by a punch —
    ///   passing one in here will report a large delta by construction, and that is the correct
    ///   answer, not a bug in the harness.
    /// - Each surviving piece gets a fresh `id`, so it seeds a different dab sequence than the stroke
    ///   it came from. Irrelevant for a brush with no scatter or rotation jitter; for one that has
    ///   them, a split visibly re-rolls the grain of the pieces and that shows up here as real delta.
    ///   Whether the pieces should inherit a derived-but-stable seed is an open question.
    static func parityOfGeometricSplit(_ scenario: ParityScenario, tolerance: Int = 0) -> ParityReport? {
        let paint = paintStroke(scenario)
        let erase = eraseStroke(scenario)
        let backdrop = backdropElement(scenario)

        // Ground truth is unchanged: the raster layer really is erased.
        let texture = rasterBase(scenario, backdrop: backdrop)
        stamp(paint, into: texture, isEraser: false)
        stamp(erase, into: texture, isEraser: true)

        guard let sweep = VectorEraser.Sweep(samples: erase.samples, brush: erase.brush,
                                             size: erase.size) else { return nil }
        let cuts = StrokeGeometry.mergedCuts(VectorEraser.cutRanges(in: paint.samples, sweep: sweep),
                                             clampedTo: 0...CGFloat(max(paint.samples.count - 1, 0)))
        let pieces: [VectorElement] = StrokeGeometry.splitStroke(paint.samples, removing: cuts).map { run in
            var piece = paint
            piece.id = UUID()
            piece.samples = paint.samples.replacingSamples(run)
            return .stroke(piece)
        }

        let elements = (backdrop.map { [$0] } ?? []) + pieces
        let vector = VectorCanvas(size: scenario.canvasSize, elements: elements).render()
        return report(raster: texture.renderToUIImage(), vector: vector,
                      size: scenario.canvasSize, tolerance: tolerance)
    }
}

/// The hybrid eraser's acceptance test for Mode 1, as a headless logic test.
///
/// The whole hybrid design rests on one assumption: that a retained `.erase` element renders
/// *exactly* what a raster layer would have produced. If it does not, "indistinguishable from raster"
/// is false and the fallback the design leans on is not a fallback at all — so this is checked at
/// zero tolerance across the brush/opacity/backdrop matrix, rather than at a comfortable epsilon.
///
/// Same arrangement as `VectorEraserLogicTests` and `StrokeGeometryLogicTests`: the engine files are
/// compiled into this target as well as the app, so their types are local to this module and there is
/// no `@testable import PaintSoftware` (which would make every name ambiguous between the two copies).
/// Nothing here drives a simulator.
final class RasterVectorParityLogicTests: XCTestCase {

    // MARK: - The scene

    private static let canvasSize = CGSize(width: 128, height: 128)

    /// A horizontal run across the middle of the canvas with pressure ramping along it, so the
    /// brush's size and opacity dynamics are actually exercised rather than pinned at one value.
    private static let paintSamples: StrokeSamples = ramp(from: CGPoint(x: 24, y: 64),
                                                           to: CGPoint(x: 104, y: 64),
                                                           count: 9, from: 0.45, to: 1)

    private static func ramp(from start: CGPoint, to end: CGPoint, count: Int,
                             from p0: CGFloat, to p1: CGFloat) -> StrokeSamples {
        StrokeSamples((0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            return VectorSample(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t,
                                pressure: p0 + (p1 - p0) * t)
        }, channels: .pressureOnly)
    }

    /// The three gesture shapes the acceptance matrix runs. The paint stroke is 24 wide, so its ink
    /// spans y ∈ [52, 76].
    private enum Gesture: String, CaseIterable {
        /// Straight across the line — the case a geometric split handles cleanly.
        case squareCut
        /// Across at 45°, so the cut boundary lands between samples on both edges.
        case diagonalCut
        /// Along the stroke, high enough that a radius-8 nib reaches only to y == 62: it shaves the
        /// top ~10 points off a 24-wide line and leaves the rest. A split cannot express this at all,
        /// which is precisely why the punch has to be exact.
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

    private static let paintID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    private static let eraserID = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!

    private func scenario(brush: Brush, eraserBrush: Brush? = nil, eraserOpacity: Double,
                          gesture: Gesture, backdrop: ParityScenario.Backdrop,
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
                       eraserSize: 16,
                       eraserOpacity: eraserOpacity,
                       eraserSamples: gesture.samples,
                       backdrop: backdrop,
                       paintID: Self.paintID,
                       eraserID: Self.eraserID)
    }

    // MARK: - The acceptance matrix

    /// The brush axis. `hardRound` (hardness 0.95) and `softRound` (hardness 0.15) are the two ends
    /// of the falloff that matters — the alpha gate exists because the soft one's edge alpha is below
    /// 1 even at full geometric coverage.
    private static let brushes = [TestBrushes.hardRound, TestBrushes.softRound]

    /// Full opacity, and `0.4` as the case that must produce a real partial fade rather than a binary
    /// cut.
    private static let eraserOpacities: [Double] = [1, 0.4]

    /// Runs brush × eraser-opacity × gesture for one backdrop. One `runActivity` per case, so a
    /// failure names the case instead of leaving twelve identical-looking assertions to sort out.
    private func assertPunchMatchesRaster(over backdropName: String, _ backdrop: ParityScenario.Backdrop,
                                          file: StaticString = #filePath, line: UInt = #line) {
        for brush in Self.brushes {
            for eraserOpacity in Self.eraserOpacities {
                for gesture in Gesture.allCases {
                    let name = "\(brush.name) / eraser opacity \(eraserOpacity) / \(gesture.label) / \(backdropName)"
                    let scene = scenario(brush: brush, eraserOpacity: eraserOpacity,
                                         gesture: gesture, backdrop: backdrop, name: name)
                    XCTContext.runActivity(named: scene.name) { _ in
                        guard let report = RasterVectorParity.parityOfRetainedPunch(scene) else {
                            return XCTFail("Could not read back both tiers for \(scene.name)", file: file, line: line)
                        }
                        XCTAssertTrue(report.isExact,
                                      "\(scene.name) — the retained erase element is not pixel-identical to raster erasing: \(report.diagnostic)",
                                      file: file, line: line)
                    }
                }
            }
        }
    }

    func testPunchOverABareStrokeIsPixelIdenticalToRasterErasing() {
        assertPunchMatchesRaster(over: "bare stroke", .none)
    }

    /// The punch must reach *everything* beneath it, fills included — which is why
    /// `renderLocalContent`'s rule 3 keeps an `.erase` element out of any transparency layer. If that
    /// rule regressed, the vector tier would leave the fill intact where the raster tier removed it,
    /// and the delta here would be the fill's own colour rather than a rounding artefact.
    func testPunchOverAVectorFillIsPixelIdenticalToRasterErasing() {
        let rect = CGRect(x: 8, y: 40, width: 112, height: 48)
        assertPunchMatchesRaster(over: "over a fill",
                                 .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1), rect))
    }

    func testPunchOverAPlacedImageIsPixelIdenticalToRasterErasing() {
        assertPunchMatchesRaster(over: "over a placed image",
                                 .image(UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1),
                                        CGSize(width: 64, height: 64)))
    }

    // MARK: - Guards on the matrix itself

    /// The matrix above compares two renders and passes when they agree. Two renders of *nothing*
    /// also agree, so without this a gesture that missed the stroke entirely — or an erase element
    /// that silently stopped being drawn in both tiers — would sail through twelve green assertions.
    /// This pins that each gesture actually removes ink from the vector render.
    func testEachGestureActuallyRemovesInkSoTheMatrixIsNotVacuous() {
        for gesture in Gesture.allCases {
            let scene = scenario(brush: TestBrushes.hardRound, eraserOpacity: 1,
                                 gesture: gesture, backdrop: .none)
            let paint = RasterVectorParity.paintStroke(scene)
            let erase = RasterVectorParity.eraseStroke(scene)
            let before = VectorCanvas(size: scene.canvasSize, elements: [.stroke(paint)]).render()
            let after = VectorCanvas(size: scene.canvasSize,
                                     elements: [.stroke(paint), .stroke(erase)]).render()
            guard let report = RasterVectorParity.report(raster: before, vector: after,
                                                         size: scene.canvasSize) else {
                return XCTFail("Could not read back the before/after renders for \(gesture.label)")
            }
            XCTAssertGreaterThan(report.differingPixelCount, 200,
                                 "\(gesture.label) barely changed the render, so the parity matrix would be measuring nothing: \(report.diagnostic)")
            XCTAssertGreaterThan(report.maxChannelDelta, 128,
                                 "\(gesture.label) should remove ink outright somewhere, not just soften it: \(report.diagnostic)")
        }
    }

    /// The other way the matrix could be vacuous: a backdrop that never rendered would make the "over
    /// a fill" and "over a placed image" runs into duplicates of the bare one. This pins both that the
    /// backdrop is really there and that the punch reaches it — erasing everything beneath, fills and
    /// placed images included, which is what `renderLocalContent`'s rule 3 keeps true by
    /// never letting an `.erase` element sit inside a transparency layer.
    ///
    /// The probe is at (64, 40): under the square cut's path, inside both backdrops, and clear of the
    /// paint stroke's own ink (which spans y ∈ [52, 76]) — so whatever is found there came from the
    /// backdrop alone.
    func testThePunchReachesTheBackdropSoTheBackdropCasesAreNotVacuous() {
        let backdrops: [(String, ParityScenario.Backdrop)] = [
            ("fill", .fill(CodableColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
                           CGRect(x: 8, y: 40, width: 112, height: 48))),
            ("placed image", .image(UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1),
                                    CGSize(width: 64, height: 64)))
        ]
        let alphaIndex = (40 * Int(Self.canvasSize.width) + 64) * 4 + 3

        for (name, backdrop) in backdrops {
            let scene = scenario(brush: TestBrushes.hardRound, eraserOpacity: 1,
                                 gesture: .squareCut, backdrop: backdrop)
            guard let element = RasterVectorParity.backdropElement(scene),
                  let intact = RasterVectorParity.premultipliedBytes(
                    of: VectorCanvas(size: scene.canvasSize, elements: [element]).render(),
                    size: scene.canvasSize),
                  let punched = RasterVectorParity.premultipliedBytes(
                    of: RasterVectorParity.tiers(scene).vector, size: scene.canvasSize) else {
                return XCTFail("Could not read back the \(name) backdrop")
            }
            XCTAssertEqual(intact[alphaIndex], 255, "The \(name) backdrop should cover the probe point")
            XCTAssertEqual(punched[alphaIndex], 0,
                           "A full-opacity erase element should punch straight through the \(name) beneath it")
        }
    }

    /// A partial-opacity eraser has to *fade* rather than cut, or "real partial fade" is
    /// only a claim about a code path nobody measured. Erasing at 0.4 must leave a band of ink that a
    /// full-opacity pass over the same gesture removes completely.
    func testAPartialOpacityEraserFadesRatherThanCuts() {
        let full = scenario(brush: TestBrushes.hardRound, eraserOpacity: 1,
                            gesture: .squareCut, backdrop: .none)
        let partial = scenario(brush: TestBrushes.hardRound, eraserOpacity: 0.4,
                               gesture: .squareCut, backdrop: .none)
        guard let bytes = RasterVectorParity.premultipliedBytes(of: RasterVectorParity.tiers(partial).vector,
                                                                size: partial.canvasSize),
              let cleared = RasterVectorParity.premultipliedBytes(of: RasterVectorParity.tiers(full).vector,
                                                                  size: full.canvasSize) else {
            return XCTFail("Could not read back the erased renders")
        }
        // Dead centre of the paint stroke, right under the eraser's path.
        let index = (64 * Int(Self.canvasSize.width) + 64) * 4 + 3
        XCTAssertEqual(cleared[index], 0, "A full-opacity eraser should clear the stroke outright")
        XCTAssertGreaterThan(bytes[index], 0, "A 0.4-opacity eraser should leave a partial fade, not a hole")
        XCTAssertLessThan(bytes[index], 255, "A 0.4-opacity eraser should still remove some of the ink")
    }

    // MARK: - The random field

    /// Every brush in the matrix carries `scatter == 0` and `rotationJitter == 0`, so none of them can
    /// catch the two tiers drawing from different randomness. This does: a scattering brush places
    /// every dab through `DabRandom`, so identical output is only possible if both tiers address the
    /// same field at the same arc lengths (BRUSH.md §4).
    ///
    /// **Two rasterizers, one walk** — which is the limit of what this file can say about randomness.
    /// It cannot notice a split, a refit, a spacing edit or a punch moving a draw, because both sides
    /// walk the identical samples; `DabRandomLogicTests` is where those live.
    func testAScatteringBrushMatchesBecauseBothTiersDrawFromOneField() {
        var scattering = TestBrushes.hardRound
        scattering.dab.scatter = 0.5
        let scene = scenario(brush: scattering, eraserOpacity: 1, gesture: .squareCut, backdrop: .none)
        guard let report = RasterVectorParity.parityOfRetainedPunch(scene) else {
            return XCTFail("Could not read back both tiers")
        }
        XCTAssertTrue(report.isExact,
                      "A scattering brush must replay to the same dabs on both tiers: \(report.diagnostic)")
    }

    /// The negative control for the test above: hand the raster tier a different field and the two
    /// tiers must diverge. Without this, a harness that accidentally compared an image with itself
    /// would look just as green.
    func testADifferentFieldOnTheRasterTierDoesDivergeSoTheFieldTestIsNotVacuous() {
        var scattering = TestBrushes.hardRound
        scattering.dab.scatter = 0.5
        let scene = scenario(brush: scattering, eraserOpacity: 1, gesture: .squareCut, backdrop: .none)
        let paint = RasterVectorParity.paintStroke(scene)
        let erase = RasterVectorParity.eraseStroke(scene)

        let texture = RasterLayerTexture.empty(size: scene.canvasSize)
        let samples = paint.samples
        BrushStamper.stampStroke(into: texture, samples: samples, brush: paint.brush,
                                 color: paint.uiColor, brushSize: paint.size,
                                 brushOpacity: paint.opacity, isEraser: false,
                                 random: DabRandom(seed: DabRandom.seed(for: Self.eraserID)))  // deliberately the wrong field
        RasterVectorParity.stamp(erase, into: texture, isEraser: true)

        let vector = VectorCanvas(size: scene.canvasSize,
                                  elements: [.stroke(paint), .stroke(erase)]).render()
        guard let report = RasterVectorParity.report(raster: texture.renderToUIImage(), vector: vector,
                                                     size: scene.canvasSize) else {
            return XCTFail("Could not read back both tiers")
        }
        XCTAssertFalse(report.isExact,
                       "A mis-seeded scattering brush should not match, or the parity harness is comparing something other than the pixels")
    }

    // MARK: - The split's measurement hook

    /// Not an assertion about the split's quality — this only pins that
    /// `RasterVectorParity.parityOfGeometricSplit` runs end to end and returns a report, so the hook
    /// itself is known to work.
    func testTheGeometricSplitHookProducesAReport() {
        let scene = scenario(brush: TestBrushes.hardRound, eraserOpacity: 1,
                             gesture: .squareCut, backdrop: .none)
        guard let report = RasterVectorParity.parityOfGeometricSplit(scene) else {
            return XCTFail("The Phase 4c measurement hook should produce a report")
        }
        XCTAssertEqual(report.totalPixelCount,
                       Int(Self.canvasSize.width) * Int(Self.canvasSize.height))
        // Recorded rather than asserted: this is the number a clean-cut gate would be tuned against.
        XCTContext.runActivity(named: "geometric split parity — \(report.diagnostic)") { _ in }
    }
}
