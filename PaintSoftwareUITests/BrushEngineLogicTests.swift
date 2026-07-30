import XCTest

/// Pure-logic tests for the brush engine's math — `BrushDynamics` pressure curves and
/// `StrokeStabilizer`'s smoothing — run as plain `XCTestCase` methods (no `XCUIApplication`, no
/// simulator gestures) so they exercise exactly the same code the app draws with, without needing a
/// real touch/pencil.
///
/// Living in `PaintSoftwareUITests` rather than a dedicated unit-test target, per this repo's
/// engine-rewrite instructions (adding a new unit-test target means `.pbxproj` target/scheme
/// surgery this effort intentionally avoids). A `bundle.ui-testing` product doesn't link against
/// the app binary the way a real unit-test target's `BUNDLE_LOADER`/`TEST_HOST` does (confirmed by
/// trying `@testable import PaintSoftware` here first: it type-checked fine but failed to *link*,
/// "symbol(s) not found for architecture arm64" — the declarations are visible via the app's
/// `.swiftmodule`, but the executable code lives only inside PaintSoftware.app's own Mach-O binary,
/// which nothing else links against). `Engine/Brush.swift` and `Engine/StrokeStabilizer.swift` are
/// therefore compiled a second time directly into *this* target too (see the project file's "Engine
/// sources shared with PaintSoftwareUITests" group and this target's Sources build phase) — both
/// files are pure Foundation/CoreGraphics with no UIKit or other app dependency, so that's a
/// harmless, ordinary multi-target-membership source file, not a fork of the logic. Their types
/// (`Brush`, `BrushDynamics`, `BrushGrain`, `StrokeStabilizer`) are consequently local to this
/// module already — no import needed (and no `@testable import PaintSoftware` either, which would
/// make every one of those names ambiguous between the two copies).
final class BrushEngineLogicTests: XCTestCase {

    // MARK: - BrushDynamics.sizeFraction

    func testSizeFractionIsFixedWhenSizePressureIsZero() {
        let dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 0, minSizeFraction: 0.2)
        // sizePressure == 0 means pressure has no effect at all: fraction should be 1 regardless
        // of how light or hard the touch is.
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 1), 1, accuracy: 0.0001)
    }

    func testSizeFractionSpansMinSizeFractionToOneWhenSizePressureIsMax() {
        let dynamics = BrushDynamics(sizePressure: 1, opacityPressure: 0, minSizeFraction: 0.3)
        // sizePressure == 1: at zero pressure the stamp should shrink to exactly minSizeFraction,
        // and grow linearly up to the full 1.0 at maximum pressure.
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 0.5), 0.65, accuracy: 0.0001)
    }

    func testSizeFractionIncreasesMonotonicallyWithPressure() {
        let dynamics = BrushDynamics(sizePressure: 0.7, opacityPressure: 0, minSizeFraction: 0.25)
        var previous = dynamics.sizeFraction(forPressure: 0)
        for step in stride(from: 0.1, through: 1.0, by: 0.1) {
            let value = dynamics.sizeFraction(forPressure: step)
            XCTAssertGreaterThanOrEqual(value, previous, "sizeFraction should never decrease as pressure increases")
            previous = value
        }
    }

    func testSizeFractionClampsOutOfRangePressure() {
        let dynamics = BrushDynamics.default
        XCTAssertEqual(dynamics.sizeFraction(forPressure: -5), dynamics.sizeFraction(forPressure: 0), accuracy: 0.0001)
        XCTAssertEqual(dynamics.sizeFraction(forPressure: 5), dynamics.sizeFraction(forPressure: 1), accuracy: 0.0001)
    }

    // MARK: - BrushDynamics.opacityFraction

    func testOpacityFractionIsFixedWhenOpacityPressureIsZero() {
        let dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 0, minSizeFraction: 1)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 1), 1, accuracy: 0.0001)
    }

    func testOpacityFractionTracksPressureDirectlyWhenOpacityPressureIsMax() {
        let dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 1, minSizeFraction: 1)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(dynamics.opacityFraction(forPressure: 1), 1, accuracy: 0.0001)
    }

    // MARK: - BrushGrain.noiseValue

    func testGrainNoiseValueIsDeterministicForSamePoint() {
        let a = BrushGrain.noiseValue(atX: 42.5, y: 17.25, scale: 1.2, rotation: 0)
        let b = BrushGrain.noiseValue(atX: 42.5, y: 17.25, scale: 1.2, rotation: 0)
        XCTAssertEqual(a, b, "The same position must always yield the same grain value, or grain would flicker stamp to stamp")
    }

    func testGrainNoiseValueStaysWithinUnitRange() {
        for i in stride(from: 0, to: 500, by: 7) {
            let value = BrushGrain.noiseValue(atX: Double(i) * 3.1, y: Double(i) * -1.7, scale: 1.0, rotation: 0.3)
            XCTAssertGreaterThanOrEqual(value, -0.01, "noiseValue drifted below the expected ~0...1 range at sample \(i)")
            XCTAssertLessThanOrEqual(value, 1.01, "noiseValue drifted above the expected ~0...1 range at sample \(i)")
        }
    }

    // MARK: - StrokeStabilizer

    func testStabilizerWithZeroStabilizationTracksInputExactly() {
        var stabilizer = StrokeStabilizer(stabilization: 0)
        stabilizer.reset(to: CGPoint(x: 0, y: 0))
        let output = stabilizer.update(rawPoint: CGPoint(x: 100, y: 50))
        XCTAssertEqual(output.x, 100, accuracy: 0.0001, "Zero stabilization should snap straight to the raw point")
        XCTAssertEqual(output.y, 50, accuracy: 0.0001)
    }

    func testStabilizerResetSnapsExactlyToTouchDownPoint() {
        var stabilizer = StrokeStabilizer(stabilization: 0.9)
        stabilizer.reset(to: CGPoint(x: 200, y: 300))
        XCTAssertEqual(stabilizer.current?.x, 200)
        XCTAssertEqual(stabilizer.current?.y, 300)
    }

    /// Feeds the same jittery synthetic zigzag through two stabilizers — one with no smoothing, one
    /// heavily smoothed — and asserts the smoothed output has strictly lower variance around the
    /// straight-line trend than the raw input does, i.e. it actually damps the jitter out rather
    /// than just being "different."
    func testHigherStabilizationSmoothsJitterMoreThanRawInput() {
        // A straight-line trend plus a sharp zigzag jitter riding on top of it.
        var rawXs: [CGFloat] = []
        for i in 0..<40 {
            let trend: CGFloat = CGFloat(i) * 5
            let jitter: CGFloat = (i % 2 == 0) ? 8 : -8
            rawXs.append(trend + jitter)
        }

        var unsmoothed = StrokeStabilizer(stabilization: 0)
        var smoothed = StrokeStabilizer(stabilization: 0.85)
        unsmoothed.reset(to: CGPoint(x: rawXs[0], y: 0))
        smoothed.reset(to: CGPoint(x: rawXs[0], y: 0))

        var unsmoothedOutputs: [CGFloat] = []
        var smoothedOutputs: [CGFloat] = []
        for x in rawXs {
            unsmoothedOutputs.append(unsmoothed.update(rawPoint: CGPoint(x: x, y: 0)).x)
            smoothedOutputs.append(smoothed.update(rawPoint: CGPoint(x: x, y: 0)).x)
        }

        func jitterEnergy(_ values: [CGFloat]) -> CGFloat {
            // Sum of squared second differences: large for a sharp zigzag, near zero for a smooth
            // (even if still sloped) line.
            guard values.count > 2 else { return 0 }
            var total: CGFloat = 0
            for i in 1..<(values.count - 1) {
                let secondDiff = values[i + 1] - 2 * values[i] + values[i - 1]
                total += secondDiff * secondDiff
            }
            return total
        }

        let rawJitter = jitterEnergy(unsmoothedOutputs)
        let smoothedJitter = jitterEnergy(smoothedOutputs)
        XCTAssertLessThan(smoothedJitter, rawJitter, "A heavily-stabilized stroke should have far less zigzag jitter than an unsmoothed one")
    }

    /// With higher stabilization, the trailing point should lag further behind the raw input at any
    /// given step along a steady linear motion — the "trails further behind" behavior the stabilizer
    /// is meant to produce.
    func testHigherStabilizationTrailsFurtherBehindRawInput() {
        var lowStabilization = StrokeStabilizer(stabilization: 0.2)
        var highStabilization = StrokeStabilizer(stabilization: 0.8)
        lowStabilization.reset(to: .zero)
        highStabilization.reset(to: .zero)

        var lowLag: CGFloat = 0
        var highLag: CGFloat = 0
        for i in 1...20 {
            let raw = CGPoint(x: CGFloat(i) * 10, y: 0)
            let lowOutput = lowStabilization.update(rawPoint: raw)
            let highOutput = highStabilization.update(rawPoint: raw)
            lowLag = raw.x - lowOutput.x
            highLag = raw.x - highOutput.x
        }
        XCTAssertGreaterThan(highLag, lowLag, "Higher stabilization should trail further behind the raw touch than lower stabilization")
    }

    func testStabilizerEventuallyCatchesUpToAHeldStillPoint() {
        var stabilizer = StrokeStabilizer(stabilization: 0.95)
        stabilizer.reset(to: CGPoint(x: 0, y: 0))
        let target = CGPoint(x: 500, y: 500)
        var last = CGPoint(x: 0, y: 0)
        for _ in 0..<400 {
            last = stabilizer.update(rawPoint: target)
        }
        XCTAssertEqual(last.x, target.x, accuracy: 0.5, "Even maximal stabilization should converge to a held-still point given enough updates, not stall short of it forever")
        XCTAssertEqual(last.y, target.y, accuracy: 0.5)
    }

    // MARK: - stampCircle's alpha profile

    /// `stampCircle` caches its radial gradient across dabs, which it can only do because the
    /// per-dab alpha is *not* baked into the gradient's colour stops — it is applied separately with
    /// `CGContext.setAlpha`. These tests pin the resulting alpha profile so that substitution can't
    /// silently drift: if someone re-bakes alpha into the stops, or the two techniques turn out not
    /// to compose the way `RasterLayerTexture.dabGradients` documents, the rendered dab changes and
    /// these fail. Nothing else in the suite looks at stamped pixel values.

    /// Reads a texture's pixels back as straight (un-premultiplied) RGBA bytes.
    private func rgbaPixels(of texture: RasterLayerTexture) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = texture.renderToUIImage().cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (bytes, width, height) : nil
    }

    private func alpha(_ pixels: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> CGFloat {
        CGFloat(pixels.bytes[(y * pixels.width + x) * 4 + 3]) / 255
    }

    /// A fully hard dab (hardness 1 puts the transparent stop at the very edge) stamped at alpha
    /// `a` must land alpha `a` at its centre — i.e. the requested per-dab opacity survives the
    /// gradient-plus-`setAlpha` composition exactly, not scaled or squared by it.
    func testStampCircleCentreAlphaMatchesRequestedAlpha() {
        for requested in [CGFloat(0.25), 0.5, 0.75, 1.0] {
            let texture = RasterLayerTexture(size: CGSize(width: 64, height: 64))
            texture.stampCircle(at: CGPoint(x: 32, y: 32), radius: 12, color: .black,
                                alpha: requested, hardness: 1)
            guard let pixels = rgbaPixels(of: texture) else {
                return XCTFail("Could not read back the stamped texture")
            }
            // 1/255 for the 8-bit quantisation of the destination bitmap, plus a little slack for
            // CG's gradient sampling right at the centre point.
            XCTAssertEqual(alpha(pixels, x: 32, y: 32), requested, accuracy: 0.02,
                           "A hardness-1 dab requested at alpha \(requested) should render that alpha at its centre")
        }
    }

    /// The falloff shape: hardness sets where the opaque core ends, and alpha decays to nothing by
    /// the dab's outer radius. Checked at hardness 0.5, where the core stop sits halfway out — the
    /// midpoint stays at full requested alpha and the rim is clear.
    func testStampCircleFalloffHoldsCoreThenFadesToTransparent() {
        let texture = RasterLayerTexture(size: CGSize(width: 64, height: 64))
        let requested: CGFloat = 0.8
        texture.stampCircle(at: CGPoint(x: 32, y: 32), radius: 20, color: .black,
                            alpha: requested, hardness: 0.5)
        guard let pixels = rgbaPixels(of: texture) else {
            return XCTFail("Could not read back the stamped texture")
        }

        XCTAssertEqual(alpha(pixels, x: 32, y: 32), requested, accuracy: 0.02,
                       "The core of the dab carries the full requested alpha")
        // Just inside the core boundary (hardness 0.5 of radius 20 = 10px out) is still full alpha.
        XCTAssertEqual(alpha(pixels, x: 41, y: 32), requested, accuracy: 0.03,
                       "Alpha should not start falling off until past the hardness-defined core")
        // Halfway through the falloff band (15px out of 20) is about half the requested alpha.
        XCTAssertEqual(alpha(pixels, x: 47, y: 32), requested * 0.5, accuracy: 0.08,
                       "Alpha should fall off linearly through the band between the core and the rim")
        // `options: []` means nothing is painted past endRadius at all.
        XCTAssertEqual(alpha(pixels, x: 54, y: 32), 0, accuracy: 0.01,
                       "Nothing should be painted beyond the dab's radius")
    }

    /// Erasing composites the same alpha profile through `.destinationOut`, so a half-alpha eraser
    /// dab removes half of what was there. This is the case where `setAlpha` had to be verified
    /// separately: it multiplies *source* alpha, which is what `.destinationOut` reads.
    func testStampCircleErasesInProportionToRequestedAlpha() {
        let texture = RasterLayerTexture(size: CGSize(width: 64, height: 64))
        texture.stampCircle(at: CGPoint(x: 32, y: 32), radius: 20, color: .black, alpha: 1, hardness: 1)
        texture.stampCircle(at: CGPoint(x: 32, y: 32), radius: 12, color: .black, alpha: 0.5,
                            hardness: 1, blendMode: .destinationOut)
        guard let pixels = rgbaPixels(of: texture) else {
            return XCTFail("Could not read back the stamped texture")
        }
        XCTAssertEqual(alpha(pixels, x: 32, y: 32), 0.5, accuracy: 0.02,
                       "A 0.5-alpha eraser dab over opaque ink should leave half of it behind")
    }

    // MARK: - Vector render isolation

    /// `VectorCanvas.renderLocalContent` stamps strokes straight into its `UIGraphicsImageRenderer`
    /// context now, instead of into a throwaway `RasterLayerTexture` that was then composited in. The
    /// scratch texture *isolated* the strokes from the fills and images beneath them, so dropping it
    /// naively would let a non-normal brush blend with that backdrop and change the render. A
    /// transparency layer restores the isolation; this test is what proves it is there.
    ///
    /// The colours are chosen so the two behaviours cannot be confused. A **green** stroke set to
    /// **multiply** laid over a **red** fill renders green when isolated (the stroke layer composites
    /// source-over), but `multiply((0,1,0), (1,0,0))` = black if the dab blends directly against the
    /// fill. Green vs. black is unambiguous.
    func testVectorMultiplyStrokeDoesNotBlendWithTheFillBeneathIt() {
        let size = CGSize(width: 64, height: 64)
        let fillPath = CGPath(rect: CGRect(x: 0, y: 0, width: 64, height: 64), transform: nil)
        let fill = VectorFillElement(path: fillPath,
                                     color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let brush = Self.opaqueTestBrush(blendMode: .multiply)
        let stroke = VectorStroke(brush: brush,
                                  color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1),
                                  size: 20, opacity: 1,
                                  samples: [VectorSample(x: 32, y: 32, pressure: 1),
                                            VectorSample(x: 32, y: 32, pressure: 1)])
        let canvas = VectorCanvas(size: size, strokes: [stroke], fills: [fill])

        guard let pixels = rgbaPixels(of: canvas.render(), width: 64, height: 64) else {
            return XCTFail("Could not read back the rendered vector canvas")
        }
        let (r, g, b) = rgb(pixels, x: 32, y: 32)
        XCTAssertGreaterThan(g, 0.8, "The multiply stroke should composite source-over onto the fill, staying green")
        XCTAssertLessThan(r, 0.2, "A red component here means the stroke blended with the red fill beneath it instead of being isolated from it")
        XCTAssertLessThan(b, 0.2)

        // Sanity: away from the stroke, the fill itself is untouched red.
        let (fr, fg, _) = rgb(pixels, x: 4, y: 4)
        XCTAssertGreaterThan(fr, 0.8, "The fill should still render red where the stroke doesn't cover it")
        XCTAssertLessThan(fg, 0.2)
    }

    /// The ordinary case, and the one that must not have regressed: a plain `.normal` stroke over a
    /// fill still lands on top of it. Source-over is associative, so this needs no isolation — but if
    /// the transparency-layer condition were inverted, or the dabs stopped reaching the context at
    /// all, this is what would catch it.
    func testVectorNormalStrokeStillPaintsOverTheFill() {
        let size = CGSize(width: 64, height: 64)
        let fillPath = CGPath(rect: CGRect(x: 0, y: 0, width: 64, height: 64), transform: nil)
        let fill = VectorFillElement(path: fillPath,
                                     color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let brush = Self.opaqueTestBrush(blendMode: .normal)
        let stroke = VectorStroke(brush: brush,
                                  color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                  size: 20, opacity: 1,
                                  samples: [VectorSample(x: 32, y: 32, pressure: 1),
                                            VectorSample(x: 32, y: 32, pressure: 1)])
        let canvas = VectorCanvas(size: size, strokes: [stroke], fills: [fill])

        guard let pixels = rgbaPixels(of: canvas.render(), width: 64, height: 64) else {
            return XCTFail("Could not read back the rendered vector canvas")
        }
        let (r, _, b) = rgb(pixels, x: 32, y: 32)
        XCTAssertGreaterThan(b, 0.8, "A normal blue stroke should paint over the red fill")
        XCTAssertLessThan(r, 0.2)
    }

    /// A fully deterministic, fully opaque brush: no pressure dynamics, no grain, no scatter, no
    /// rotation jitter, hard edge. Any of those would make a single-pixel colour assertion flaky.
    private static func opaqueTestBrush(blendMode: BrushBlendMode) -> Brush {
        Brush(name: "Test", shape: .hardRound, size: 20, opacity: 1, flow: 1,
              spacingFraction: 0.1, hardness: 1, stabilization: 0, scatter: 0,
              rotationJitter: 0, dynamics: .fixed, grain: .disabled, blendMode: blendMode)
    }

    private func rgbaPixels(of image: UIImage, width: Int, height: Int) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (bytes, width, height) : nil
    }

    /// Un-premultiplied RGB at a pixel. The dabs under test are fully opaque, so dividing out alpha
    /// is only guarding against a near-1 alpha skewing the comparison.
    private func rgb(_ pixels: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> (CGFloat, CGFloat, CGFloat) {
        let i = (y * pixels.width + x) * 4
        let a = CGFloat(pixels.bytes[i + 3]) / 255
        guard a > 0 else { return (0, 0, 0) }
        return (CGFloat(pixels.bytes[i]) / 255 / a,
                CGFloat(pixels.bytes[i + 1]) / 255 / a,
                CGFloat(pixels.bytes[i + 2]) / 255 / a)
    }

    // MARK: - Display list: `VectorElement`

    private static let canvasSide = 64
    private static let canvasSize = CGSize(width: 64, height: 64)

    private func opaqueFill(_ color: CodableColor) -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(origin: .zero, size: Self.canvasSize), transform: nil),
                          color: color)
    }

    /// A stroke that lands as one hard, opaque blob at the centre of the canvas. Two identical samples
    /// so `stampStroke` lays exactly one dab, which keeps single-pixel assertions exact.
    private func centreStroke(_ color: CodableColor, blendMode: BrushBlendMode = .normal,
                              composite: StrokeComposite = .paint) -> VectorStroke {
        VectorStroke(brush: Self.opaqueTestBrush(blendMode: blendMode), color: color,
                     size: 20, opacity: 1,
                     samples: [VectorSample(x: 32, y: 32, pressure: 1),
                               VectorSample(x: 32, y: 32, pressure: 1)],
                     composite: composite)
    }

    private func solidImage(_ color: UIColor, side: CGFloat = 16) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func placedImage(_ color: UIColor) -> VectorImageElement {
        VectorImageElement(image: solidImage(color),
                           transform: LayerTransform(position: CGPoint(x: 32, y: 32), scale: 1, rotation: 0),
                           fileName: "placed.png")
    }

    private func renderedBytes(_ canvas: VectorCanvas) -> [UInt8]? {
        rgbaPixels(of: canvas.render(), width: Self.canvasSide, height: Self.canvasSide)?.bytes
    }

    private func alphaAtCentre(_ canvas: VectorCanvas) -> CGFloat? {
        guard let pixels = rgbaPixels(of: canvas.render(), width: Self.canvasSide, height: Self.canvasSide) else { return nil }
        return alpha(pixels, x: 32, y: 32)
    }

    /// One-word tag per element kind, so an expected z-order reads as a literal in the assertions.
    private func kinds(_ elements: [VectorElement]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    private func kinds(_ elements: [VectorCanvasData.ElementData]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    /// The compatibility accessors are the whole reason this refactor stayed small: ~30 call sites read
    /// and assign `.strokes`/`.fills`/`.images` as if the three arrays were still there. The undo/redo
    /// path is the one that assigns wholesale (`StrokeCanvasView.registerVectorUndo` snapshots
    /// `canvas.strokes` and later puts it straight back), so a get→set round trip must be an identity on
    /// the display list — otherwise every undo would drift a stroke above or below a fill.
    func testKindAccessorGetSetRoundTripPreservesElementOrder() {
        let fill = opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let image = placedImage(.green)
        let first = centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        let second = centreStroke(CodableColor(red: 1, green: 1, blue: 0, alpha: 1))
        let original: [VectorElement] = [.fill(fill), .image(image), .stroke(first), .stroke(second)]

        for label in ["strokes", "fills", "images"] {
            let canvas = VectorCanvas(size: Self.canvasSize, elements: original)
            switch label {
            case "strokes": canvas.strokes = canvas.strokes
            case "fills": canvas.fills = canvas.fills
            default: canvas.images = canvas.images
            }
            XCTAssertEqual(canvas.elements.map(\.id), original.map(\.id),
                           "Reading and re-assigning .\(label) must leave the display list exactly as it was")
        }
    }

    /// The setter contract on an empty bucket. `registerVectorFillUndo`'s redo does
    /// `canvas.fills = newFills` on a canvas whose fills the matching undo just removed, so "there were
    /// none of this kind" cannot mean "append at the end" — that would put a redone flood fill *above*
    /// the strokes it originally went under.
    func testAssigningFillsToACanvasWithNoneKeepsThemBeneathTheStrokes() {
        let stroke = centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stroke(stroke)])
        canvas.fills = [opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))]

        XCTAssertEqual(kinds(canvas.elements), ["fill", "stroke"],
                       "A fill assigned back onto a canvas that currently has none belongs under the strokes, matching addFill")
    }

    /// Every `add…` keeps the legacy fills→images→strokes z-order, which is what makes Phase 1 free of
    /// visible change: flood-filling after drawing a line still puts the fill *under* the line. A naive
    /// append into one list would cover the line up.
    func testAddingElementsPreservesTheLegacyFillsThenImagesThenStrokesOrder() {
        let canvas = VectorCanvas(size: Self.canvasSize)
        canvas.addStroke(centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1)))
        canvas.addFill(opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1)))
        canvas.addImage(placedImage(.green))
        canvas.addStroke(centreStroke(CodableColor(red: 1, green: 1, blue: 0, alpha: 1)))

        XCTAssertEqual(kinds(canvas.elements), ["fill", "image", "stroke", "stroke"],
                       "Adds are sorted by kind, so content built through the public API renders in the pre-display-list order")
    }

    // MARK: - Display list: `StrokeComposite` decoding

    /// Encodes `value`, drops `keys` from the resulting JSON object, and hands back the JSON — the way
    /// to build an authentic "saved by an older build" payload without checking a blob into the suite.
    private func jsonObject<T: Encodable>(_ value: T, removing keys: [String] = []) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 1)
        }
        for key in keys { object.removeValue(forKey: key) }
        return object
    }

    /// The migration hinge. A `Codable` struct's *synthesized* decoder ignores property defaults and
    /// throws `keyNotFound`, so without the hand-written `init(from:)` on `VectorStroke` every project
    /// saved before `composite` existed would fail to load. This is the test that would catch that.
    func testVectorStrokeDecodesAsPaintWhenTheCompositeKeyIsAbsent() throws {
        let legacy = try jsonObject(centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1)),
                                    removing: ["composite"])
        XCTAssertNil(legacy["composite"], "Setup: the key must actually be missing for this to test anything")

        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(VectorStroke.self, from: data)
        XCTAssertEqual(decoded.composite, .paint, "A stroke saved before the field existed is a paint stroke")
    }

    func testVectorStrokeRoundTripsTheEraseComposite() throws {
        let eraser = centreStroke(CodableColor(red: 0, green: 0, blue: 0, alpha: 1), composite: .erase)
        let decoded = try JSONDecoder().decode(VectorStroke.self, from: JSONEncoder().encode(eraser))
        XCTAssertEqual(decoded.composite, .erase)
        XCTAssertEqual(decoded.id, eraser.id)
        XCTAssertEqual(decoded.samples, eraser.samples)
    }

    // MARK: - Display list: persistence migration

    /// Builds a pre-display-list `VectorCanvasData` payload: three parallel arrays, no `elements` key.
    private func legacyCanvasJSON(strokes: [VectorStroke], fills: [VectorFillElement],
                                  images: [VectorCanvasData.ImageRef],
                                  transform: [Double] = [1, 0, 0, 1, 0, 0]) throws -> Data {
        let root: [String: Any] = [
            "strokes": try strokes.map { try jsonObject($0) },
            "fills": try fills.map { try jsonObject($0) },
            "images": try images.map { try jsonObject($0) },
            "transform": transform
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// A legacy file carries no z-order at all, so decoding has to *reconstruct* the order the old
    /// renderer hard-coded — all fills, then all images, then all strokes. Get this wrong and every
    /// existing project opens with its fills on top of its linework.
    func testLegacyVectorCanvasDataDecodesAsFillsThenImagesThenStrokes() throws {
        let data = try legacyCanvasJSON(
            strokes: [centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1)),
                      centreStroke(CodableColor(red: 1, green: 1, blue: 0, alpha: 1))],
            fills: [opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
                    opaqueFill(CodableColor(red: 0, green: 1, blue: 1, alpha: 1))],
            images: [VectorCanvasData.ImageRef(fileName: "a.png", x: 32, y: 32, scale: 1, rotation: 0)])

        let payload = try JSONDecoder().decode(VectorCanvasData.self, from: data)
        XCTAssertEqual(kinds(payload.elements), ["fill", "fill", "image", "stroke", "stroke"])
        XCTAssertTrue(payload.affineTransform.isIdentity)
        // The kind-filtered reads still work for callers that only want one bucket.
        XCTAssertEqual(payload.strokes.count, 2)
        XCTAssertEqual(payload.fills.count, 2)
        XCTAssertEqual(payload.images.map(\.fileName), ["a.png"])
    }

    /// legacy JSON → decode → encode → decode must be stable, and must render the same both times.
    /// The second decode goes through the *new* `elements` branch, so this is what proves the migration
    /// is a fixed point rather than a one-way reshuffle.
    func testLegacyPayloadReEncodesAndRendersIdenticallyAfterMigration() throws {
        let stroke = centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        let fill = opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let ref = VectorCanvasData.ImageRef(fileName: "a.png", x: 20, y: 20, scale: 1, rotation: 0)
        let legacy = try legacyCanvasJSON(strokes: [stroke], fills: [fill], images: [ref])

        let first = try JSONDecoder().decode(VectorCanvasData.self, from: legacy)
        let migrated = try JSONEncoder().encode(first)
        let second = try JSONDecoder().decode(VectorCanvasData.self, from: migrated)

        XCTAssertNotNil(try JSONSerialization.jsonObject(with: migrated) as? [String: Any],
                        "Setup: the migrated payload should be a JSON object")
        let object = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        XCTAssertNotNil(object["elements"], "The re-encoded payload writes the ordered display list")
        XCTAssertNil(object["strokes"], "The legacy parallel arrays are not mirrored back out")

        XCTAssertEqual(kinds(second.elements), kinds(first.elements))
        XCTAssertEqual(second.elements.compactMap { if case .stroke(let s) = $0 { return s.id } else { return nil } },
                       first.elements.compactMap { if case .stroke(let s) = $0 { return s.id } else { return nil } })

        // …and the pixels. One resolver for both so the placed image is byte-identical either way.
        let resolve: (VectorCanvasData.ImageRef) -> UIImage? = { [weak self] _ in self?.solidImage(.green) }
        let before = VectorCanvas(size: Self.canvasSize, elements: first.elements(resolvingImages: resolve),
                                  transform: first.affineTransform)
        let after = VectorCanvas(size: Self.canvasSize, elements: second.elements(resolvingImages: resolve),
                                 transform: second.affineTransform)
        XCTAssertEqual(renderedBytes(before), renderedBytes(after),
                       "A migrated payload must render exactly as the legacy one it came from")

        // And both must match what the pre-change three-array construction produced, which is the
        // actual acceptance criterion for this phase.
        let legacyShaped = VectorCanvas(size: Self.canvasSize, strokes: [stroke], fills: [fill],
                                        images: [VectorImageElement(image: solidImage(.green),
                                                                    transform: LayerTransform(position: CGPoint(x: 20, y: 20), scale: 1, rotation: 0),
                                                                    fileName: "a.png")])
        XCTAssertEqual(renderedBytes(before), renderedBytes(legacyShaped),
                       "The reconstructed display list must render identically to the fixed fills→images→strokes order it replaces")
    }

    // MARK: - Display list: eraser z-order semantics

    /// "The eraser lowers the alpha of everything beneath it" — fills included, which three parallel
    /// arrays could never express because strokes were always drawn last but erasing was a *destructive*
    /// sample edit that never touched a fill.
    func testEraseStrokeAfterAFillRemovesAlphaFromThatFill() {
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: [.fill(opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))),
                                             .stroke(centreStroke(CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                                  composite: .erase))])
        guard let pixels = rgbaPixels(of: canvas.render(), width: Self.canvasSide, height: Self.canvasSide) else {
            return XCTFail("Could not read back the rendered vector canvas")
        }
        XCTAssertEqual(alpha(pixels, x: 32, y: 32), 0, accuracy: 0.02,
                       "The erase stroke should punch through the fill beneath it, not just through other strokes")
        XCTAssertEqual(alpha(pixels, x: 4, y: 4), 1, accuracy: 0.02,
                       "Away from the eraser the fill is untouched")
    }

    /// The bug this whole refactor exists to prevent. With erasers pinned to the end of a fixed render
    /// order, a stroke drawn *after* an erase would be eaten by it. Position in the display list is what
    /// decides, and it has to decide in both directions.
    func testStrokeDrawnAfterAnEraseElementIsNotEatenByIt() {
        let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        let eraser = centreStroke(CodableColor(red: 0, green: 0, blue: 0, alpha: 1), composite: .erase)
        let fill = opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))

        let strokeAfter = VectorCanvas(size: Self.canvasSize,
                                       elements: [.fill(fill), .stroke(eraser), .stroke(centreStroke(blue))])
        guard let pixels = rgbaPixels(of: strokeAfter.render(), width: Self.canvasSide, height: Self.canvasSide) else {
            return XCTFail("Could not read back the rendered vector canvas")
        }
        XCTAssertEqual(alpha(pixels, x: 32, y: 32), 1, accuracy: 0.02,
                       "A stroke later in the display list than the erase element must survive it")
        let (r, _, b) = rgb(pixels, x: 32, y: 32)
        XCTAssertGreaterThan(b, 0.8, "…and it must be the stroke's own colour")
        XCTAssertLessThan(r, 0.2)

        // The mirror image: same three elements, eraser last, and now the stroke *is* erased. Same
        // content, different z-order, opposite result — which is the point.
        let strokeBefore = VectorCanvas(size: Self.canvasSize,
                                        elements: [.fill(fill), .stroke(centreStroke(blue)), .stroke(eraser)])
        XCTAssertEqual(alphaAtCentre(strokeBefore) ?? -1, 0, accuracy: 0.02,
                       "An erase element after the stroke removes it, so order is genuinely what decides")
    }

    /// Group boundaries. An `.erase` element ends the current paint run, and the next run has to get its
    /// own transparency layer if it needs one — otherwise a non-normal brush drawn after an erase would
    /// start blending with the fill beneath it, the exact regression
    /// `testVectorMultiplyStrokeDoesNotBlendWithTheFillBeneathIt` pins for the simple case.
    func testANonNormalRunAfterAnEraseElementIsStillIsolated() {
        // The eraser sits in a corner so it doesn't overlap the assertion point.
        var eraser = centreStroke(CodableColor(red: 0, green: 0, blue: 0, alpha: 1), composite: .erase)
        eraser.samples = [VectorSample(x: 4, y: 4, pressure: 1), VectorSample(x: 4, y: 4, pressure: 1)]
        let canvas = VectorCanvas(size: Self.canvasSize,
                                  elements: [.fill(opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))),
                                             .stroke(eraser),
                                             .stroke(centreStroke(CodableColor(red: 0, green: 1, blue: 0, alpha: 1),
                                                                  blendMode: .multiply))])
        guard let pixels = rgbaPixels(of: canvas.render(), width: Self.canvasSide, height: Self.canvasSide) else {
            return XCTFail("Could not read back the rendered vector canvas")
        }
        let (r, g, b) = rgb(pixels, x: 32, y: 32)
        XCTAssertGreaterThan(g, 0.8, "The multiply run after the erase element is still isolated, so it stays green")
        XCTAssertLessThan(r, 0.2, "A red component means the run blended with the fill beneath it")
        XCTAssertLessThan(b, 0.2)
        XCTAssertEqual(alpha(pixels, x: 4, y: 4), 0, accuracy: 0.02,
                       "…and the erase element still punched its own hole in the fill")
    }

    /// The cache must not leak one dab's alpha into the next. Stamping full alpha *after* a faint
    /// dab, at the same colour and hardness (so the second stamp is a cache hit), still has to paint
    /// fully opaque — a stale baked-in alpha would show up here as a faint second dab.
    func testStampCircleCacheHitDoesNotReuseThePreviousDabsAlpha() {
        let texture = RasterLayerTexture(size: CGSize(width: 64, height: 64))
        texture.stampCircle(at: CGPoint(x: 16, y: 32), radius: 8, color: .black, alpha: 0.1, hardness: 1)
        texture.stampCircle(at: CGPoint(x: 48, y: 32), radius: 8, color: .black, alpha: 1.0, hardness: 1)
        guard let pixels = rgbaPixels(of: texture) else {
            return XCTFail("Could not read back the stamped texture")
        }
        XCTAssertEqual(texture.dabGradientCacheHits, 1,
                       "Same colour and hardness: the second dab must be served from the cache, or this test isn't exercising the case it claims to")
        XCTAssertEqual(alpha(pixels, x: 16, y: 32), 0.1, accuracy: 0.02, "The faint dab stays faint")
        XCTAssertEqual(alpha(pixels, x: 48, y: 32), 1.0, accuracy: 0.02,
                       "The opaque dab must be opaque despite reusing the faint dab's cached gradient")
    }
}
