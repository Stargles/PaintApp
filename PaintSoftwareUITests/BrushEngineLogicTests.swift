import XCTest

/// Pure-logic tests for the brush engine's math — BRUSH.md §6's pressure rows and
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
/// (`Brush`, `BrushModulations`, `StrokeStabilizer`) are consequently local to this module already —
/// no import needed (and no `@testable import PaintSoftware` either, which would make every one of
/// those names ambiguous between the two copies).
final class BrushEngineLogicTests: XCTestCase {

    // MARK: - BRUSH.md §6 — the pressure rows that replaced `BrushDynamics`

    /// The two rows every shipped preset carries, as a brush. `size`'s base is `1 - amount` and
    /// `flow`'s is too, which is the pairing that makes a full press reach full width — see
    /// `BrushLibrary` and `StrokeSettingsPanel.pressureAmountBinding`.
    ///
    /// **The second row drives `flow` since §12 stage 8.** BRUSH.md §2.11 makes opacity the stroke's
    /// cap rather than a dab's multiplier, and the row that used to be spelled `opacity ← pressure`
    /// was always the arithmetic of *what one stamp lays down*. The parameter keeps the name the
    /// tests below read it by; the output it drives is flow.
    private func pressureBrush(size: Double, atZero: Double, opacity: Double) -> Brush {
        Brush(name: "fixture", tip: .round, size: 10,
              dab: BrushDabSettings(size: 1 - size, flow: 1 - opacity),
              modulations: BrushModulations([
                .sizeFromPressure(amount: size, atZero: atZero),
                .flowFromPressure(amount: opacity)
              ]))
    }

    private func sizeFraction(_ brush: Brush, _ pressure: CGFloat) -> Double {
        brush.dabValues(atPressure: pressure).size
    }

    private func opacityFraction(_ brush: Brush, _ pressure: CGFloat) -> Double {
        brush.dabValues(atPressure: pressure).flow
    }

    func testSizeFractionIsFixedWhenSizePressureIsZero() {
        let brush = pressureBrush(size: 0, atZero: 0.2, opacity: 0)
        // A `size ← pressure` row at amount 0 means pressure has no effect at all: the fraction is
        // the base, 1, regardless of how light or hard the touch is.
        XCTAssertEqual(sizeFraction(brush, 0), 1, accuracy: 0.0001)
        XCTAssertEqual(sizeFraction(brush, 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(sizeFraction(brush, 1), 1, accuracy: 0.0001)
    }

    func testSizeFractionSpansTheRampFloorToOneWhenTheRowIsFullAmount() {
        let brush = pressureBrush(size: 1, atZero: 0.3, opacity: 0)
        // Amount 1: at zero pressure the stamp shrinks to exactly the ramp's floor, and grows
        // linearly to the full 1.0 at maximum pressure.
        XCTAssertEqual(sizeFraction(brush, 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(sizeFraction(brush, 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(sizeFraction(brush, 0.5), 0.65, accuracy: 0.0001)
    }

    func testSizeFractionIncreasesMonotonicallyWithPressure() {
        let brush = pressureBrush(size: 0.7, atZero: 0.25, opacity: 0)
        var previous = sizeFraction(brush, 0)
        for step in stride(from: 0.1, through: 1.0, by: 0.1) {
            let value = sizeFraction(brush, CGFloat(step))
            XCTAssertGreaterThanOrEqual(value, previous, "the size row should never decrease as pressure increases")
            previous = value
        }
    }

    func testSizeFractionClampsOutOfRangePressure() {
        let brush = BrushLibrary.softRound
        XCTAssertEqual(sizeFraction(brush, -5), sizeFraction(brush, 0), accuracy: 0.0001)
        XCTAssertEqual(sizeFraction(brush, 5), sizeFraction(brush, 1), accuracy: 0.0001)
    }

    func testOpacityFractionIsFixedWhenOpacityPressureIsZero() {
        let brush = pressureBrush(size: 0, atZero: 1, opacity: 0)
        XCTAssertEqual(opacityFraction(brush, 0), 1, accuracy: 0.0001)
        XCTAssertEqual(opacityFraction(brush, 1), 1, accuracy: 0.0001)
    }

    func testOpacityFractionTracksPressureDirectlyWhenOpacityPressureIsMax() {
        let brush = pressureBrush(size: 0, atZero: 1, opacity: 1)
        XCTAssertEqual(opacityFraction(brush, 0), 0, accuracy: 0.0001)
        XCTAssertEqual(opacityFraction(brush, 0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(opacityFraction(brush, 1), 1, accuracy: 0.0001)
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

    /// A fully deterministic, fully opaque brush: no pressure dynamics, no scatter, no
    /// rotation jitter, hard edge. Any of those would make a single-pixel colour assertion flaky.
    private static func opaqueTestBrush(blendMode: BrushBlendMode) -> Brush {
        Brush(name: "Test", tip: .round, size: 20, opacity: 1, dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1, scatter: 0, angle: BrushAngleSettings(jitter: 0)), stroke: BrushStrokeSettings(stabilization: 0, blendMode: blendMode))
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
            case .text: return "text"
            case .video: return "video"
            case .stroke(let stroke): return stroke.composite == .erase ? "erase" : "stroke"
            }
        }
    }

    private func kinds(_ elements: [VectorCanvasData.ElementData]) -> [String] {
        elements.map {
            switch $0 {
            case .fill: return "fill"
            case .image: return "image"
            case .text: return "text"
            case .video: return "video"
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

    /// The setter contract on an empty bucket: with no existing element of that kind there is no
    /// position to preserve, so the positional splice falls back to `insertionIndex` and the fill goes
    /// under the strokes. That is the right answer for the one thing still reconstructing a list this
    /// way — a legacy project whose fills were all beneath the line art — and it is why fill *undo*
    /// does not go through this setter at all any more: an appended fill has a z-position this cannot
    /// recover, so `registerVectorElementsUndo` swaps the whole array instead.
    func testAssigningFillsToACanvasWithNoneKeepsThemBeneathTheStrokes() {
        let stroke = centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [.stroke(stroke)])
        canvas.fills = [opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))]

        XCTAssertEqual(kinds(canvas.elements), ["fill", "stroke"],
                       "A fill assigned back onto a canvas that currently has none belongs under the strokes, matching addFill")
    }

    /// `addStroke` and `addImage` still insert by kind, keeping the legacy images→strokes z-order —
    /// **`addFill` no longer does, and the change is deliberate.** It appends, so a fill lands on top
    /// of what is already on the layer (LASSO_FILL.md §2a, the owner's *"Cover everything"* of
    /// 2026-08-21); this used to assert `["fill", "image", "stroke", "stroke"]` on the same four calls,
    /// from when a fill drawn after a line was required to go *under* it.
    func testAddingElementsKeepsTheKindOrderExceptForAFillWhichGoesOnTop() {
        let canvas = VectorCanvas(size: Self.canvasSize)
        canvas.addStroke(centreStroke(CodableColor(red: 0, green: 0, blue: 1, alpha: 1)))
        canvas.addFill(opaqueFill(CodableColor(red: 1, green: 0, blue: 0, alpha: 1)))
        canvas.addImage(placedImage(.green))
        canvas.addStroke(centreStroke(CodableColor(red: 1, green: 1, blue: 0, alpha: 1)))

        XCTAssertEqual(kinds(canvas.elements), ["image", "stroke", "fill", "stroke"],
                       "The fill sits where the artist put it — above the stroke that was already "
                       + "there — while the other two adds still sort by kind")
    }

    // MARK: - Display list: importing two images (owner report 7)
    //
    // `addImageToActiveVectorLayer` used to hard-code every import to the canvas centre with no
    // cascade, so a second image landed exactly on the first — same stored `position`, same `fit` for
    // same-aspect images — and nothing in the app could separate them afterwards: Move only carries the
    // whole cel, and `splitForLassoMove` (below) selects an image purely by its stored centre, so two
    // bit-identical centres can never be told apart by any loop. `VectorCanvas.addImage(canvasSpaceElement:)`
    // fixes both halves at once: it maps the canvas-space centre through `_transform.inverted()` before
    // storing (storage is local, like every other element on this canvas) and cascades by a step
    // converted to local units, both under the one lock acquisition that reads `_transform`.

    /// The bug as the owner saw it: two imports, one canvas, no separation. Not a magic-number check —
    /// just that the two stored positions cannot be the same point, which is the one thing that made
    /// the second image unrecoverable.
    func testAddingTwoImagesToAVectorLayerPlacesThemAtDistinctPositions() {
        let canvas = VectorCanvas(size: Self.canvasSize)
        let first = canvas.addImage(canvasSpaceElement: solidImage(.red),
                                    canvasPosition: CGPoint(x: 32, y: 32), canvasFit: 0.5)
        let second = canvas.addImage(canvasSpaceElement: solidImage(.green),
                                     canvasPosition: CGPoint(x: 32, y: 32), canvasFit: 0.5)

        XCTAssertNotEqual(first.transform.position, second.transform.position,
                          "A second image centred on the same canvas point as the first must not land "
                          + "on the exact same stored position, or it is permanently indistinguishable from it")
    }

    /// The naive fix — adding a step straight to the canvas-centre expression — is wrong because that
    /// value is local-space storage while the centre is computed in canvas space: on a layer with a
    /// non-identity transform it both mis-places the image and bakes the space error into the cascade
    /// too. This pins the correct mapping directly: an imported image's local position, carried back
    /// through the very `transform` it was imported under, must land exactly on the canvas point the
    /// artist imported at (for the first image, before any cascade), and its local `scale` must render
    /// back out at the `fit` it was given.
    func testAddImageCanvasSpaceElementMapsPositionAndScaleThroughTheLayersTransform() {
        let transform = CGAffineTransform(translationX: 100, y: 50).scaledBy(x: 2, y: 2)
        let canvas = VectorCanvas(size: Self.canvasSize, elements: [], transform: transform)
        let canvasCentre = CGPoint(x: Self.canvasSize.width / 2, y: Self.canvasSize.height / 2)
        let fit: CGFloat = 0.8

        let element = canvas.addImage(canvasSpaceElement: solidImage(.blue), canvasPosition: canvasCentre, canvasFit: fit)

        let mappedBackToCanvas = element.transform.position.applying(transform)
        XCTAssertEqual(mappedBackToCanvas.x, canvasCentre.x, accuracy: 0.001,
                       "The stored local position must map back to the canvas centre through the layer's own transform")
        XCTAssertEqual(mappedBackToCanvas.y, canvasCentre.y, accuracy: 0.001,
                       "The stored local position must map back to the canvas centre through the layer's own transform")

        XCTAssertEqual(element.transform.scale * canvas.transformScale, fit, accuracy: 0.0001,
                       "The stored local scale must render back out at the canvas-space `fit` it was given")
    }

    /// The only per-element move path in the app is the lasso: `splitForLassoMove` decides membership
    /// purely by an element's stored centre (`VectorLayer.swift`, the `.image` case). A loop drawn
    /// tightly around the first image's own centre must therefore pick up the first image and leave the
    /// second behind — which is only possible at all because the two centres are no longer identical.
    func testALassoLoopAroundOneImageDoesNotSelectTheOther() {
        let canvas = VectorCanvas(size: Self.canvasSize)
        let first = canvas.addImage(canvasSpaceElement: solidImage(.red),
                                    canvasPosition: CGPoint(x: 32, y: 32), canvasFit: 0.5)
        let second = canvas.addImage(canvasSpaceElement: solidImage(.green),
                                     canvasPosition: CGPoint(x: 32, y: 32), canvasFit: 0.5)
        XCTAssertNotEqual(first.transform.position, second.transform.position, "Setup: see the distinct-positions test above")

        let radius: CGFloat = 6
        let loop = CGPath(ellipseIn: CGRect(x: first.transform.position.x - radius,
                                            y: first.transform.position.y - radius,
                                            width: radius * 2, height: radius * 2), transform: nil)

        guard let split = canvas.splitForLassoMove(insideLocalPath: loop) else {
            return XCTFail("A loop drawn around the first image's own centre should select something")
        }
        XCTAssertTrue(split.insideIDs.contains(first.id), "The loop was drawn around the first image's own centre")
        XCTAssertFalse(split.insideIDs.contains(second.id), "The second image's centre must fall outside a loop drawn only around the first")
    }

    /// Undo removes the second import; redo must put back the very same element at the very same
    /// cascaded offset, not reconstruct a fresh one. `addImageToActiveVectorLayer` binds `element` once
    /// from `VectorCanvas.addImage(canvasSpaceElement:)`'s return value, outside both closures, so redo
    /// replays that captured value — recomputing the cascade inside the redo closure instead (from the
    /// cel's live image count, read at redo time rather than at the moment of the original import) would
    /// still often land on the same number by coincidence, but it would build a *new* `VectorImageElement`
    /// with a fresh id, which this test also catches.
    func testUndoThenRedoOfASecondImageImportReplaysTheSameElementAtTheSameOffset() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        XCTAssertTrue(manager.addImageToActiveVectorLayer(solidImage(.red)))
        XCTAssertTrue(manager.addImageToActiveVectorLayer(solidImage(.green)))

        guard let celIdx = manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame),
              let vector = manager.layers[0].cels[celIdx].vector else {
            return XCTFail("Setup: expected a vector cel holding the two imported images")
        }
        XCTAssertEqual(vector.images.count, 2, "Setup: both imports should have landed")
        let secondBeforeUndo = vector.images[1]

        manager.undo()
        XCTAssertEqual(vector.images.count, 1, "Undo should remove only the second import")

        manager.redo()
        XCTAssertEqual(vector.images.count, 2, "Redo should restore the second import")
        let secondAfterRedo = vector.images[1]

        XCTAssertEqual(secondAfterRedo.id, secondBeforeUndo.id,
                       "Redo should replay the very element undo removed, not construct a fresh one")
        XCTAssertEqual(secondAfterRedo.transform.position, secondBeforeUndo.transform.position,
                       "Redo must re-place the second image at the identical cascaded offset it had before undo")
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
        let before = VectorCanvas(size: Self.canvasSize,
                                  elements: first.canvasSpaceElements(resolvingImages: resolve,
                                                                      resolvingVideos: { _ in nil }))
        let after = VectorCanvas(size: Self.canvasSize,
                                 elements: second.canvasSpaceElements(resolvingImages: resolve,
                                                                      resolvingVideos: { _ in nil }))
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

    // MARK: - stampStroke's visible range

    /// `visibleRange` has to be a *filter over the original walk*, not a re-derivation of it — that is
    /// the entire reason a cut stroke can now be pixel-exact (see `DabLattice`). Stamping two
    /// complementary ranges of one stroke into one texture must therefore reproduce stamping it whole,
    /// byte for byte.
    ///
    /// The cut is deliberately at a fractional parameter and off any dab position, so nothing about the
    /// result is an artefact of the boundary landing on a sample or on a lattice step.
    func testComplementaryVisibleRangesReproduceTheWholeStrokeExactly() {
        let brush = BrushLibrary.hardRound
        // Curved, with a pressure ramp: both the dab spacing carry across segments and the pressure
        // interpolation have to survive the filter, not just the positions.
        let samples = StrokeSamples((0..<9).map { i -> VectorSample in
            let t = CGFloat(i) / 8
            return VectorSample(point: CGPoint(x: 6 + 52 * t, y: 30 + 12 * sin(t * .pi)),
                                pressure: 0.35 + 0.65 * t)
        }, channels: .pressureOnly)
        let cut: CGFloat = 3.37

        func stamp(into texture: RasterLayerTexture, visibleRange: ClosedRange<CGFloat>?) {
            BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                     brushSize: 9, brushOpacity: 1, random: DabRandom(seed: 99),
                                     visibleRange: visibleRange)
        }

        let whole = RasterLayerTexture(size: Self.canvasSize)
        stamp(into: whole, visibleRange: nil)
        let head = RasterLayerTexture(size: Self.canvasSize)
        stamp(into: head, visibleRange: 0...cut)
        let pieces = RasterLayerTexture(size: Self.canvasSize)
        stamp(into: pieces, visibleRange: 0...cut)
        stamp(into: pieces, visibleRange: cut...8)

        guard let wholeBytes = rgbaPixels(of: whole)?.bytes,
              let headBytes = rgbaPixels(of: head)?.bytes,
              let pieceBytes = rgbaPixels(of: pieces)?.bytes else {
            return XCTFail("Could not read back the stamped textures")
        }
        XCTAssertEqual(pieceBytes, wholeBytes,
                       "Two complementary visible ranges must lay exactly the dabs the uncut stroke laid")
        XCTAssertNotEqual(headBytes, wholeBytes,
                          "Setup: half the range alone should be visibly less ink, or this test compares nothing")
    }

    /// A piece's lattice has to survive a save. It is the only record of where that piece's dabs go, so
    /// a project reopened without it would show every cut stroke re-phased on its own first sample —
    /// precisely the artefact the split exists to avoid, arriving a day later than the cut. And an
    /// ordinary stroke must not start writing the key, so files that contain no pieces are unchanged.
    func testAPieceLatticeSurvivesEncodingAndAnOrdinaryStrokeDoesNotCarryOne() throws {
        let parent = VectorStroke(brush: BrushLibrary.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 9, opacity: 1,
                                  // Pressures in *even* 255ths, and coordinates on whole points, so
                                  // this fixture survives TODO item (8)'s storage quantisation exactly
                                  // — including the midpoint sample `splitStrokeRuns` interpolates at
                                  // 2.5, whose numerator is then still an integer. That is what lets
                                  // the assertions below stay the strict, byte-exact ones they were:
                                  // this test's subject is the lattice, not the codec, and widening
                                  // its tolerance to accommodate quantisation would have cost the
                                  // suite its only comparison of *pixels* across a save.
                                  // `SampleCodingLogicTests` is where lossy values are pinned.
                                  samples: StrokeSamples((0..<5).map {
                                      VectorSample(x: 8 + CGFloat($0) * 12, y: 32,
                                                   pressure: CGFloat(50 + $0 * 10) / 255)
                                  }, channels: .pressureOnly))
        guard let run = StrokeGeometry.splitStrokeRuns(parent.samples, removing: [2.5...3.5]).first else {
            return XCTFail("Setup: cutting the middle out should leave a head run")
        }
        var piece = parent
        piece.id = UUID()
        piece.samples = parent.samples.replacingSamples(run.samples)
        piece.lattice = DabLattice(samples: parent.samples, parameters: run.parameters)

        // **Both operands of both assertions reach the in-memory original**, and that is deliberate
        // rather than incidental. Comparing a decode against another decode is tautological under a
        // format that is a fixed point — a `DabLattice.encode` that dropped every pressure to 1 would
        // satisfy it, and every reloaded cut stroke would come back untapered.
        let decoded = try JSONDecoder().decode(VectorStroke.self,
                                               from: try JSONEncoder().encode(piece))
        XCTAssertEqual(decoded.lattice, piece.lattice, "The lattice must round-trip intact")
        let before = try XCTUnwrap(renderedBytes(VectorCanvas(size: Self.canvasSize, elements: [.stroke(piece)])),
                                   "Setup: the saved piece must render")
        let after = try XCTUnwrap(renderedBytes(VectorCanvas(size: Self.canvasSize, elements: [.stroke(decoded)])),
                                  "Setup: the reloaded piece must render")
        XCTAssertEqual(after, before,
                       "A reloaded piece must render exactly as the one that was saved")

        let plain = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(parent)) as? [String: Any]
        XCTAssertNil(plain?["lattice"],
                     "A stroke that is nobody's piece writes no lattice key")
        XCTAssertNil(try JSONDecoder().decode(VectorStroke.self, from: try JSONEncoder().encode(parent)).lattice,
                     "…and decodes back without one")
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

    // MARK: - Real-size stamp preview (SizePreview.swift)
    //
    // The window that pops up beside a held size slider. Its whole reason to exist is that the
    // number on the slider is in *canvas* points and the mark the artist is about to judge is in
    // *screen* points, and the two differ by the canvas zoom — a 40-point brush at 0.3x is a
    // 12-point mark. Every assertion below is on `SizePreviewGeometry`/`SizePreviewVisibility`
    // rather than on the view, because `Views/SizePreviewWindow.swift` is not compiled into this
    // target and nothing inside it could be reached from here.

    /// The load-bearing one: the stamp is `size x zoom`, at every zoom the canvas offers.
    func testSizePreviewStampIsBrushSizeTimesCanvasScaleAcrossTheZoomRange() {
        let request = SizePreviewRequest(sliderID: "brushPanel.sizeSlider", tool: .brush, side: .leading)
        for zoom in [CGFloat(0.125), 0.3, 0.5, 1, 2, 3, 4] {
            for brushSize in [CGFloat(1), 5, 40, 200] {
                let size = request.toolSize(brushSize: brushSize, eraserSize: 999)
                let geometry = SizePreviewGeometry(toolSize: size, canvasScale: zoom)
                XCTAssertEqual(geometry.stampDiameter, brushSize * zoom, accuracy: 0.0001,
                               "A \(brushSize)-point brush at \(zoom)x must preview as \(brushSize * zoom) screen points, not \(brushSize)")
            }
        }
    }

    /// The eraser has its own size, and the preview must read that one.
    func testSizePreviewStampReadsTheEraserSizeNotTheBrushSize() {
        let eraser = SizePreviewRequest(sliderID: "eraserPanel.sizeSlider", tool: .eraser, side: .leading)
        let brush = SizePreviewRequest(sliderID: "brushPanel.sizeSlider", tool: .brush, side: .leading)
        for zoom in [CGFloat(0.125), 0.5, 1, 2, 4] {
            let eraserGeometry = SizePreviewGeometry(toolSize: eraser.toolSize(brushSize: 5, eraserSize: 20),
                                                     canvasScale: zoom)
            XCTAssertEqual(eraserGeometry.stampDiameter, 20 * zoom, accuracy: 0.0001,
                           "The eraser preview must scale `eraserSize`, not `brushSize`")
            let brushGeometry = SizePreviewGeometry(toolSize: brush.toolSize(brushSize: 5, eraserSize: 20),
                                                    canvasScale: zoom)
            XCTAssertEqual(brushGeometry.stampDiameter, 5 * zoom, accuracy: 0.0001,
                           "…and the brush preview the other way round")
        }
        XCTAssertEqual(eraser.opacity(brushOpacity: 1, eraserOpacity: 0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(brush.opacity(brushOpacity: 1, eraserOpacity: 0.4), 1, accuracy: 0.0001)
    }

    /// Past the ceiling the window stops growing and the stamp is **not** scaled down to fit —
    /// scaling to fit would destroy the only thing the preview communicates, so it is clipped
    /// instead, and `isClipped` is what tells the view to make the crop look deliberate.
    func testSizePreviewWindowStopsGrowingButTheStampStaysRealSize() {
        let max = SizePreviewGeometry.maximumWindowSide

        let fits = SizePreviewGeometry(toolSize: 40, canvasScale: 1)
        XCTAssertEqual(fits.windowSide, 40 + 2 * SizePreviewGeometry.margin, accuracy: 0.0001,
                       "A stamp that fits gets a window sized to it plus its margins")
        XCTAssertFalse(fits.isClipped)

        for zoom in [CGFloat(2), 4] {
            let huge = SizePreviewGeometry(toolSize: 200, canvasScale: zoom)
            XCTAssertEqual(huge.windowSide, max, accuracy: 0.0001,
                           "The window must stop at its maximum instead of growing to \(200 * zoom)")
            XCTAssertEqual(huge.stampDiameter, 200 * zoom, accuracy: 0.0001,
                           "…and the stamp must still be drawn at real size, not shrunk to fit the window")
            XCTAssertTrue(huge.isClipped, "…and must say so, so the crop reads as deliberate")
        }
    }

    /// …and the other end: a hairline brush at the lowest zoom still gets a window big enough to
    /// look at, without the stamp inside it being inflated to match.
    func testSizePreviewWindowHasAFloorSoATinyStampIsStillVisible() {
        let tiny = SizePreviewGeometry(toolSize: 1, canvasScale: 0.125)
        XCTAssertEqual(tiny.windowSide, SizePreviewGeometry.minimumWindowSide, accuracy: 0.0001)
        XCTAssertEqual(tiny.stampDiameter, 0.125, accuracy: 0.0001,
                       "The floor is on the window, never on the stamp")
        XCTAssertFalse(tiny.isClipped)
    }

    // MARK: Visibility

    /// Down shows, lift hides. The owner asked for touch-down specifically, so this is driven by
    /// `Slider.onEditingChanged` and not by a value change.
    func testSizePreviewShowsOnTouchDownAndHidesOnLift() {
        let request = SizePreviewRequest(sliderID: "sideToolbar.brushSizeSlider", tool: .brush, side: .above)
        var visibility = SizePreviewVisibility()
        XCTAssertFalse(visibility.isVisible, "Nothing is showing before anything is touched")

        visibility.editingChanged(true, for: request)
        XCTAssertTrue(visibility.isVisible, "Touch-down alone must raise it, with no drag at all")
        XCTAssertEqual(visibility.tool, .brush)

        visibility.editingChanged(false, for: request)
        XCTAssertFalse(visibility.isVisible, "Lift must lower it")
    }

    /// Dragging the slider is the whole point of holding it, so a value change in between must not
    /// dismiss the window the press just raised.
    func testSizePreviewSurvivesAValueChangeWhileTheSliderIsHeld() {
        let request = SizePreviewRequest(sliderID: "brushPanel.sizeSlider", tool: .brush, side: .leading)
        var visibility = SizePreviewVisibility()
        visibility.editingChanged(true, for: request)

        // What a drag does: the binding writes a new size, and `onEditingChanged` is not called
        // again — except that SwiftUI is free to re-assert `true`, which must also be harmless.
        for newSize in [CGFloat(9), 24, 61, 200] {
            visibility.editingChanged(true, for: request)
            XCTAssertTrue(visibility.isVisible, "Still held at size \(newSize)")
            XCTAssertEqual(SizePreviewGeometry(toolSize: request.toolSize(brushSize: newSize, eraserSize: 20),
                                               canvasScale: 0.5).stampDiameter,
                           newSize * 0.5, accuracy: 0.0001,
                           "…and following the new value")
        }

        visibility.editingChanged(false, for: request)
        XCTAssertFalse(visibility.isVisible)
    }

    /// Two size sliders drive the same `brushSize` — the rail's and the panel's — so a lift has to
    /// name which one it came from or a stale one could dismiss the other's preview.
    func testSizePreviewIgnoresALiftFromADifferentSlider() {
        let rail = SizePreviewRequest(sliderID: "sideToolbar.brushSizeSlider", tool: .brush, side: .above)
        let panel = SizePreviewRequest(sliderID: "brushPanel.sizeSlider", tool: .brush, side: .leading)
        var visibility = SizePreviewVisibility()

        visibility.editingChanged(true, for: rail)
        visibility.editingChanged(false, for: panel)
        XCTAssertTrue(visibility.isVisible, "The panel's lift must not lower the rail's preview")
        XCTAssertEqual(visibility.active?.sliderID, rail.sliderID)

        visibility.editingChanged(false, for: rail)
        XCTAssertFalse(visibility.isVisible)
    }

    // MARK: Placement

    /// The rail's slider is vertical and the hand travels its whole length, so the window goes
    /// *above* it — and gets clamped back onto the screen, since a 176-point window centred on a
    /// 64-point rail hangs off the leading edge.
    func testSizePreviewWindowSitsAboveARailSliderAndInsideTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let slider = CGRect(x: 12, y: 300, width: 56, height: 150)
        let side: CGFloat = 176
        let origin = SizePreviewGeometry.windowOrigin(sliderFrame: slider, side: .above,
                                                      windowSide: side, within: screen)
        XCTAssertEqual(origin.y, slider.minY - SizePreviewGeometry.gap - side, accuracy: 0.0001,
                       "Clear above the track, where a hand on the track cannot be")
        XCTAssertGreaterThanOrEqual(origin.x, screen.minX + SizePreviewGeometry.screenInset,
                                    "…and pulled back onto the screen rather than half off it")
        XCTAssertLessThanOrEqual(origin.x + side, screen.maxX - SizePreviewGeometry.screenInset)
    }

    /// The panel's slider is horizontal inside a 300-point dropdown pinned to the trailing edge, so
    /// the window goes past its leading edge — outside the bounds the hand is inside.
    func testSizePreviewWindowSitsLeadingOfAPanelSlider() {
        let screen = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let slider = CGRect(x: 736, y: 200, width: 276, height: 30)
        let side: CGFloat = 120
        let origin = SizePreviewGeometry.windowOrigin(sliderFrame: slider, side: .leading,
                                                      windowSide: side, within: screen)
        XCTAssertEqual(origin.x, slider.minX - SizePreviewGeometry.gap - side, accuracy: 0.0001)
        XCTAssertLessThan(origin.x + side, slider.minX, "Never on top of the panel it belongs to")
        XCTAssertEqual(origin.y + side / 2, slider.midY, accuracy: 0.0001, "Level with the row")
    }

    // MARK: The stamp itself

    /// Not a grey disc: the preview goes through `BrushStamper.stampDab`, so what comes back is the
    /// real brush at the real size. Rendered at 4x zoom and read back in pixels — at 1x a point 15
    /// away from a 10-point brush's centre would be blank, and here it must be inked.
    func testSizePreviewStampRendersARealDabAtItsRealScreenSize() {
        let brush = Brush(name: "Preview", tip: .round, size: 10, opacity: 1, dab: BrushDabSettings(spacing: 0.1, hardness: 1), stroke: BrushStrokeSettings(stabilization: 0))
        let geometry = SizePreviewGeometry(toolSize: 10, canvasScale: 4)
        XCTAssertEqual(geometry.stampDiameter, 40, accuracy: 0.0001)

        let image = SizePreviewStampRenderer.stampImage(geometry: geometry, brush: brush, tool: .brush,
                                                        color: .black, opacity: 1)
        guard let cg = image.cgImage,
              let pixels = rgbaPixels(of: image, width: cg.width, height: cg.height) else {
            return XCTFail("Could not read back the preview stamp")
        }
        let scale = CGFloat(cg.width) / geometry.windowSide
        let centre = cg.width / 2

        XCTAssertEqual(alpha(pixels, x: centre, y: centre), 1, accuracy: 0.05,
                       "The dab's own centre is solid ink")
        XCTAssertEqual(alpha(pixels, x: centre + Int(15 * scale), y: centre), 1, accuracy: 0.1,
                       "15 points out is inside a 40-point stamp — this is the whole zoom claim")
        XCTAssertEqual(alpha(pixels, x: centre + Int(24 * scale), y: centre), 0, accuracy: 0.05,
                       "…and 24 points out is past its 20-point radius")
    }

    /// The eraser preview shows a removal, not eraser-coloured ink: the dab is composited
    /// `.destinationOut` through a patch of ink, so it comes back as a hole.
    func testSizePreviewEraserStampPunchesAHoleRatherThanPainting() {
        let brush = Brush(name: "Preview", tip: .round, size: 10, opacity: 1, dab: BrushDabSettings(spacing: 0.1, hardness: 1), stroke: BrushStrokeSettings(stabilization: 0))
        let geometry = SizePreviewGeometry(toolSize: 10, canvasScale: 2)
        let image = SizePreviewStampRenderer.stampImage(geometry: geometry, brush: brush, tool: .eraser,
                                                        color: .black, opacity: 1)
        guard let cg = image.cgImage,
              let pixels = rgbaPixels(of: image, width: cg.width, height: cg.height) else {
            return XCTFail("Could not read back the preview stamp")
        }
        let centre = cg.width / 2
        XCTAssertEqual(alpha(pixels, x: centre, y: centre), 0, accuracy: 0.05,
                       "Where the eraser lands there is nothing left")
        XCTAssertEqual(alpha(pixels, x: 1, y: 1), 1, accuracy: 0.05,
                       "…and outside it the ink patch it was cut from is untouched")
    }

    // MARK: The live canvas scale

    /// Silent unless a preview is up (the scale changes every frame of a pinch and this is pushed
    /// from a path that runs inside `updateUIView`), and up to date the moment one opens.
    func testCanvasDisplayScaleOnlyPublishesWhileAPreviewIsUp() {
        let scale = CanvasDisplayScale()
        scale.record(3)
        XCTAssertEqual(scale.scale, 1, accuracy: 0.0001, "Nobody is looking, so nothing is published")
        XCTAssertEqual(scale.latest, 3, accuracy: 0.0001, "…but the value is kept")

        scale.beginPublishing()
        XCTAssertEqual(scale.scale, 3, accuracy: 0.0001, "Opening a preview catches up to the canvas")

        scale.record(0.5)
        XCTAssertEqual(scale.scale, 0.5, accuracy: 0.0001, "…and then tracks it live, so a pinch resizes the stamp")

        scale.endPublishing()
        scale.record(9)
        XCTAssertEqual(scale.scale, 0.5, accuracy: 0.0001, "Silent again after the lift")
        XCTAssertEqual(scale.latest, 9, accuracy: 0.0001)
    }

    /// A degenerate transform must not poison the preview's arithmetic.
    func testCanvasDisplayScaleRejectsNonPositiveAndNonFiniteScales() {
        let scale = CanvasDisplayScale()
        scale.beginPublishing()
        scale.record(2)
        scale.record(0)
        scale.record(-1)
        scale.record(.nan)
        scale.record(.infinity)
        XCTAssertEqual(scale.scale, 2, accuracy: 0.0001)
    }

    // MARK: - StrokeScratch: the live stroke is bounded by the stroke, not by the canvas

    /// **The 16k crash, as arithmetic.** A 16383² canvas is 268 million pixels — 1 GiB of RGBA —
    /// and the live stroke used to open one of those per gesture, materialise its context on the
    /// first dab and re-image it per touch-move. A stroke covering a 100×100 patch has no business
    /// touching more than a few hundred thousand pixels, and that is what this asserts: the window
    /// holds the stroke's own dirty rect plus its growth margin, three orders of magnitude below the
    /// canvas.
    ///
    /// This is the test that goes red if the scratch is ever sized to `canvasSize` again — which is
    /// the single line the whole defect was.
    func testAStrokeOnA16kCanvasHoldsAWindowRoundTheStrokeAndNotACanvas() {
        let canvas = CGSize(width: 16383, height: 16383)
        let scratch = StrokeScratch(canvasSize: canvas, role: .additive)
        for x in stride(from: CGFloat(8000), through: 8100, by: 4) {
            scratch.stampCircle(at: CGPoint(x: x, y: 8000), radius: 6, color: .black,
                                alpha: 1, hardness: 1, blendMode: .normal)
        }
        guard let dirty = scratch.dirtyRect else {
            return XCTFail("Dabs were stamped, so the scratch has a dirty rect")
        }
        XCTAssertEqual(dirty, CGRect(x: 7994, y: 7994, width: 112, height: 12),
                       "The dirty rect is the union of the dabs, in canvas points")
        XCTAssertTrue(scratch.windowRect.contains(dirty),
                      "Every dab has to be inside the window it was stamped into")
        let canvasPixels = 16383 * 16383
        XCTAssertLessThan(scratch.windowPixelCount, canvasPixels / 1000,
                          "A 100-point stroke may not hold a canvas. Window is "
                          + "\(scratch.windowRect) = \(scratch.windowPixelCount) px against "
                          + "\(canvasPixels) px of canvas")
    }

    /// A gesture that never moves — a tap that lays one dab, or one that lays none at all — must not
    /// allocate on the promise of a stroke that may never come. Touch-down used to open the canvas
    /// buffer before the first dab was drawn.
    func testAScratchAllocatesNothingUntilTheFirstDab() {
        let scratch = StrokeScratch(canvasSize: CGSize(width: 16383, height: 16383), role: .additive)
        XCTAssertEqual(scratch.windowPixelCount, 0)
        XCTAssertNil(scratch.image)
        XCTAssertNil(scratch.dirtyRect)
    }

    /// **The sharpest form of "not proportional to canvas area": the same stroke gets the same
    /// window whatever canvas it is drawn on.** Nothing in the window's size may read `canvasSize`
    /// except the clamp at the edges, so a stroke placed well inside both canvases must produce
    /// windows that are equal — not merely both small.
    ///
    /// A ratio against the ink would be the obvious assertion and is a much weaker one: it passes
    /// for any implementation that happens to be generous, and its number moves with where the
    /// growth margin lands. Equality does not.
    func testTheWindowIsTheSameOnA4kCanvasAndOnA16kOne() {
        func window(onCanvasOfSide side: CGFloat) -> CGRect {
            let scratch = StrokeScratch(canvasSize: CGSize(width: side, height: side), role: .additive)
            for x in stride(from: CGFloat(900), through: 1100, by: 5) {
                scratch.stampCircle(at: CGPoint(x: x, y: 1000), radius: 6, color: .black,
                                    alpha: 1, hardness: 1, blendMode: .normal)
            }
            return scratch.windowRect
        }
        let small = window(onCanvasOfSide: 4096)
        let large = window(onCanvasOfSide: 16383)
        XCTAssertEqual(small, large,
                       "The window follows the stroke, so a canvas sixteen times the area must not "
                       + "change it by a pixel")
        XCTAssertFalse(small.isNull)
    }

    /// **A straight line gets a band, not a square.** The window used to outset *both* axes by half
    /// its own **longer** side, so the first growth squared the box and every growth after doubled
    /// it in both directions whatever shape the stroke was. MEASURED on the owner's iPad 9 at
    /// 16383²: one screen inch of pen travel held an 8617×8611 window — 283.1 MB — for a stroke
    /// whose own bounding box was 54 KB, against a 183.7 MB compositor budget (BUGS.md and
    /// PERFORMANCE.md §9 item 1, both 2026-09-02).
    ///
    /// The fixture is that gesture in miniature: 1212 points of travel, 12 points thick, well inside
    /// an 8192² canvas so the canvas clamp plays no part in the answer. Under the per-axis rule the
    /// window is 4576×140; under the max-of-both-axes rule it is 4576×4564, and **both assertions
    /// below fail on that number** — the first by 4564 against a bound of 268, the second by 20.9 M
    /// pixels against 1.36 M. Reverting the expression in `StrokeScratch.window(containing:)` is
    /// what this test is for, so it asserts the *shape* rather than an exact size: the growth
    /// margin's arithmetic may legitimately be re-tuned, and a band that is still a band should
    /// survive that.
    func testAStraightStrokeGetsABandAndNotASquare() {
        let scratch = StrokeScratch(canvasSize: CGSize(width: 8192, height: 8192), role: .additive)
        for x in stride(from: CGFloat(3000), through: 4200, by: 4) {
            scratch.stampCircle(at: CGPoint(x: x, y: 4000), radius: 6, color: .black,
                                alpha: 1, hardness: 1, blendMode: .normal)
        }
        guard let dirty = scratch.dirtyRect else {
            return XCTFail("Dabs were stamped, so the scratch has a dirty rect")
        }
        XCTAssertEqual(dirty, CGRect(x: 2994, y: 3994, width: 1212, height: 12),
                       "The ink is a long thin band, which is the whole premise of the test")
        XCTAssertTrue(scratch.windowRect.contains(dirty),
                      "Every dab has to be inside the window it was stamped into")

        // The axis the stroke never left keeps the extent the first dab gave it, plus at most the
        // couple of `minimumPad` outsets a wobble at the ends could have bought.
        XCTAssertLessThan(scratch.windowRect.height, dirty.height + 4 * 64,
                          "The stroke never moved vertically, so the window may not have grown "
                          + "vertically. Window is \(scratch.windowRect) round ink of \(dirty)")
        // And the area follows the ink's own band rather than the square of the stroke's length.
        let band = Int(dirty.width) * (Int(dirty.height) + 128)
        XCTAssertLessThan(scratch.windowPixelCount, band * 8,
                          "A window round a 1212×12 stroke may not cost the square of its length. "
                          + "Window is \(scratch.windowRect) = \(scratch.windowPixelCount) px "
                          + "against \(band) px of banded ink")
    }

    /// The case the per-axis rule has to get right and the one BUGS.md flags as the thing to check:
    /// a stroke that runs along one axis and then turns ninety degrees. The union carries the turn,
    /// so the second axis now grows geometrically from *its* own extent — several reallocations,
    /// each of them asymmetric, each copying the old window into a new one that is bigger in one
    /// direction only. That is the intended behaviour rather than a regression to the square, and
    /// what has to be proved about it is not its size but that it loses nothing: the commit must
    /// still be byte-for-byte what stamping into the cel would have been.
    func testAStrokeThatTurnsThroughNinetyDegreesCommitsExactly() {
        let size = CGSize(width: 512, height: 512)
        let direct = RasterLayerTexture(size: size)
        let viaScratch = RasterLayerTexture(size: size)
        let scratch = StrokeScratch(canvasSize: size, role: .additive)

        var dabs: [CGPoint] = []
        for x in stride(from: CGFloat(100), through: 400, by: 6) { dabs.append(CGPoint(x: x, y: 150)) }
        for y in stride(from: CGFloat(150), through: 400, by: 6) { dabs.append(CGPoint(x: 400, y: y)) }
        for point in dabs {
            direct.stampCircle(at: point, radius: 7, color: .black, alpha: 0.8, hardness: 0.9)
            scratch.stampCircle(at: point, radius: 7, color: .black, alpha: 0.8, hardness: 0.9,
                                blendMode: .normal)
        }
        XCTAssertGreaterThan(scratch.windowRect.height, 250,
                            "The turn is what grows the second axis — if it did not, the fixture is "
                            + "not exercising the case")
        scratch.commit(into: viaScratch)

        assertPixelsMatch(viaScratch, direct,
                          "A stroke that turns must carry every dab through every asymmetric "
                          + "reallocation the turn causes")
    }

    /// **A dab that lands where the pixels cannot go is dropped, not chased.** Off-canvas ink is
    /// storable nowhere and displayable nowhere, so growing the window to reach it would be a
    /// straight loss — and on a stroke flicked past the edge it would be a large one.
    func testADabEntirelyOffTheCanvasGrowsNothing() {
        let scratch = StrokeScratch(canvasSize: CGSize(width: 512, height: 512), role: .additive)
        scratch.stampCircle(at: CGPoint(x: 5000, y: 5000), radius: 8, color: .black,
                            alpha: 1, hardness: 1, blendMode: .normal)
        XCTAssertEqual(scratch.windowPixelCount, 0)
        XCTAssertNil(scratch.image)
    }

    /// **A dab pressed against a clamped canvas edge must not force the window to keep regrowing.**
    /// `window(containing:)`'s fast path tested `windowRect.contains(rect)` against the dab's *raw*
    /// bounding box, but `windowRect` is always clamped to the canvas — so a dab whose circle pokes
    /// past the edge (even though everything it can actually paint is already inside the window)
    /// could never satisfy that test, and every such dab took the rebuild path instead of reusing
    /// the window it already had. The rebuild path is worse than merely wasteful here: it still uses
    /// the unclamped `rect` to compute `wanted`, so `wanted` also pokes past the canvas on every
    /// call, `pad` keeps seeing `wanted > held`, and the window creeps wider and wider — from tens of
    /// points to the whole canvas — purely from dabs that never put ink anywhere the window didn't
    /// already cover.
    func testADabStraddlingAClampedEdgeDoesNotRegrowTheWindowForever() {
        let scratch = StrokeScratch(canvasSize: CGSize(width: 512, height: 512), role: .additive)
        // Pressed against the left edge: the dab's own circle (x in [-4, 8]) pokes past x = 0, but
        // everything it can actually paint (x in [0, 8]) is on-canvas from the very first dab on.
        for _ in 0..<20 {
            scratch.stampCircle(at: CGPoint(x: 2, y: 256), radius: 6, color: .black, alpha: 1,
                                hardness: 1, blendMode: .normal)
        }
        XCTAssertLessThan(scratch.windowRect.width, 256,
                          "Twenty dabs at the same point must not regrow a window whose ink never "
                          + "moved past x = 8. Window is \(scratch.windowRect)")
    }

    /// **The window's pixels have to be the cel's pixels.** A paint stroke stamped into an
    /// `.additive` scratch and committed must land where the same dabs stamped straight into the
    /// texture would have — that equality is the whole licence for the live stroke to stop touching
    /// the cel, and it holds because the window's origin is integral (so the dab's sub-pixel phase is
    /// unchanged) and source-over is associative (so compositing the window over what is already
    /// there is the same as having stamped into it).
    ///
    /// **To within `assertPixelsMatch`'s two bytes, not byte-for-byte**, which is what this comment
    /// claimed and what the code has never asserted: all three callers take the default
    /// `tolerance: 2`, and that helper's own doc explains why (compositing into an 8-bit scratch and
    /// then over the layer rounds twice where stamping straight in rounds once). The slack is bounded
    /// and does not grow with the stroke; a geometry mistake is not bounded like that.
    func testAnAdditiveScratchCommitsExactlyWhatDirectStampingWouldHave() {
        let size = CGSize(width: 256, height: 256)
        let dabs: [(CGPoint, CGFloat)] = [(CGPoint(x: 90, y: 100), 12), (CGPoint(x: 104, y: 108), 14),
                                          (CGPoint(x: 120, y: 116), 10), (CGPoint(x: 133, y: 130), 16)]

        let direct = RasterLayerTexture(size: size)
        // Existing ink underneath, so the commit has something to composite *over* — the case a
        // `.copy` of the window would silently destroy.
        direct.stampCircle(at: CGPoint(x: 110, y: 110), radius: 40, color: .red, alpha: 0.6, hardness: 1)
        let viaScratch = RasterLayerTexture(size: size)
        viaScratch.stampCircle(at: CGPoint(x: 110, y: 110), radius: 40, color: .red, alpha: 0.6, hardness: 1)

        let scratch = StrokeScratch(canvasSize: size, role: .additive)
        for (point, radius) in dabs {
            direct.stampCircle(at: point, radius: radius, color: .blue, alpha: 0.5, hardness: 0.8)
            scratch.stampCircle(at: point, radius: radius, color: .blue, alpha: 0.5, hardness: 0.8,
                                blendMode: .normal)
        }
        scratch.commit(into: viaScratch)

        assertPixelsMatch(viaScratch, direct,
                          "A paint stroke through the window must land the pixels stamping "
                          + "straight into the cel would have")
    }

    /// The same equality for the erase, which is the case that cannot be expressed as something
    /// drawn on top: the window starts from the cel's own pixels, takes `.destinationOut` punches
    /// out of them, and commits by replacing that region outright.
    func testAReplacingScratchCommitsExactlyWhatDirectErasingWouldHave() {
        let size = CGSize(width: 256, height: 256)
        let direct = RasterLayerTexture(size: size)
        direct.stampCircle(at: CGPoint(x: 128, y: 128), radius: 60, color: .green, alpha: 1, hardness: 1)
        let viaScratch = RasterLayerTexture(size: size)
        viaScratch.stampCircle(at: CGPoint(x: 128, y: 128), radius: 60, color: .green, alpha: 1, hardness: 1)

        let scratch = StrokeScratch(canvasSize: size,
                                    role: .replacing(backdrop: viaScratch.renderIfNonEmpty()))
        for x in stride(from: CGFloat(100), through: 160, by: 6) {
            direct.stampCircle(at: CGPoint(x: x, y: 128), radius: 10, color: .black, alpha: 0.7,
                               hardness: 1, blendMode: .destinationOut)
            scratch.stampCircle(at: CGPoint(x: x, y: 128), radius: 10, color: .black, alpha: 0.7,
                                hardness: 1, blendMode: .destinationOut)
        }
        scratch.commit(into: viaScratch)

        assertPixelsMatch(viaScratch, direct,
                          "An erase through the window must take away exactly what erasing straight "
                          + "into the cel would have")
    }

    /// A stroke long enough to outgrow its first window still commits exactly, which is the claim
    /// the growth path has to earn: what the old window held is copied into the new one, and the
    /// backdrop fills the ring the old one never covered.
    func testAStrokeThatOutgrowsItsWindowStillCommitsExactly() {
        let size = CGSize(width: 1024, height: 1024)
        let direct = RasterLayerTexture(size: size)
        direct.stampCircle(at: CGPoint(x: 512, y: 512), radius: 400, color: .red, alpha: 1, hardness: 1)
        let viaScratch = RasterLayerTexture(size: size)
        viaScratch.stampCircle(at: CGPoint(x: 512, y: 512), radius: 400, color: .red, alpha: 1, hardness: 1)

        let scratch = StrokeScratch(canvasSize: size,
                                    role: .replacing(backdrop: viaScratch.renderIfNonEmpty()))
        // Far longer than `minimumPad`, so the window is reallocated several times over.
        for x in stride(from: CGFloat(200), through: 820, by: 7) {
            direct.stampCircle(at: CGPoint(x: x, y: 512), radius: 9, color: .black, alpha: 1,
                               hardness: 1, blendMode: .destinationOut)
            scratch.stampCircle(at: CGPoint(x: x, y: 512), radius: 9, color: .black, alpha: 1,
                                hardness: 1, blendMode: .destinationOut)
        }
        XCTAssertGreaterThan(scratch.windowRect.width, 620, "The window followed the stroke")
        scratch.commit(into: viaScratch)

        assertPixelsMatch(viaScratch, direct,
                          "Growing the window must carry every dab it already held")
    }

    /// **Erasing a tier that has no bitmap commits nothing, and allocates nothing to do it.** There
    /// is nothing to take away, and writing transparency into the cel would materialise the very
    /// canvas-sized context this whole change exists to avoid — 1 GiB at 16383², for a no-op.
    func testAnEraserOnABlankTierLeavesItBlankAndUnallocated() {
        let raster = RasterLayerTexture(size: CGSize(width: 16383, height: 16383))
        XCTAssertFalse(raster.hasContent)
        let scratch = StrokeScratch(canvasSize: raster.size,
                                    role: .replacing(backdrop: raster.renderIfNonEmpty()))
        for x in stride(from: CGFloat(8000), through: 8060, by: 6) {
            scratch.stampCircle(at: CGPoint(x: x, y: 8000), radius: 10, color: .black, alpha: 1,
                                hardness: 1, blendMode: .destinationOut)
        }
        scratch.commit(into: raster)
        XCTAssertFalse(raster.hasContent,
                       "An erase over nothing must not be the thing that opens the canvas buffer")
    }

    /// A blank tier has no image, rather than a canvas-sized sheet of transparency. `handleBegin`
    /// used to take one of those as its pre-stroke snapshot and memoize it, so the first touch on an
    /// empty raster cel cost a whole canvas before a single dab was visible.
    func testABlankTierRendersToNoImageAtAll() {
        let raster = RasterLayerTexture(size: CGSize(width: 16383, height: 16383))
        XCTAssertNil(raster.renderIfNonEmpty(),
                     "Nothing has been drawn, so there is nothing to show and nothing to allocate")
        raster.stampCircle(at: CGPoint(x: 100, y: 100), radius: 8, color: .black, alpha: 1, hardness: 1)
        XCTAssertNotNil(raster.renderIfNonEmpty(), "…and one dab is enough to change the answer")
    }

    /// The selection clip, in the window instead of across the canvas: what the stroke put outside
    /// the path is dropped before the commit, so undo/redo only ever sees the clipped result. This
    /// used to be a canvas-sized `PixelOps.maskedComposite` against a canvas-sized pre-stroke
    /// snapshot — two more whole canvases per clipped stroke than the clip needs.
    func testTheSelectionClipDropsWhatTheStrokePutOutsideThePath() {
        let size = CGSize(width: 256, height: 256)
        let raster = RasterLayerTexture(size: size)
        let scratch = StrokeScratch(canvasSize: size, role: .additive)
        scratch.stampCircle(at: CGPoint(x: 60, y: 128), radius: 12, color: .black, alpha: 1,
                            hardness: 1, blendMode: .normal)
        scratch.stampCircle(at: CGPoint(x: 200, y: 128), radius: 12, color: .black, alpha: 1,
                            hardness: 1, blendMode: .normal)
        scratch.clip(to: CGPath(rect: CGRect(x: 0, y: 0, width: 128, height: 256), transform: nil))
        scratch.commit(into: raster)

        guard let pixels = rgbaPixels(of: raster) else {
            return XCTFail("Could not read back the committed texture")
        }
        XCTAssertEqual(alpha(pixels, x: 60, y: 128), 1, accuracy: 0.02,
                       "The dab inside the selection survives")
        XCTAssertEqual(alpha(pixels, x: 200, y: 128), 0, accuracy: 0.02,
                       "The dab outside it does not")
    }

    // MARK: - BRUSH.md §2.11 — Flow is what one stamp lays down, Opacity is what the stroke may reach

    /// **A stroke that crosses itself, as one stroke.** Along `y = 32`, sharply back to the top
    /// middle, then straight down through `x = 32` — so `(32, 32)` is covered by two passes of the
    /// same stroke and `(14, 32)` by one. Both corners turn through 135°, which `StrokePath.isCorner`
    /// takes as a crease, so both the horizontal and the vertical leg are straight chords and land on
    /// the probe points exactly.
    ///
    /// Every probe is on `y = 32` of a 64-tall canvas and the figure is symmetric about it, so
    /// nothing here can be an artefact of a y-flip in the read-back.
    private static func crossingStroke() -> StrokeSamples {
        StrokeSamples([VectorSample(x: 6, y: 32, pressure: 1),
                       VectorSample(x: 58, y: 32, pressure: 1),
                       VectorSample(x: 32, y: 6, pressure: 1),
                       VectorSample(x: 32, y: 58, pressure: 1)], channels: .pressureOnly)
    }

    /// A brush with no rows at all, so every dab lays down exactly `flow` and nothing about these
    /// tests depends on the matrix.
    private static func flatBrush(flow: Double, spacing: Double,
                                  blendMode: BrushBlendMode = .normal) -> Brush {
        Brush(name: "flow fixture", tip: .round, size: 8, opacity: 1,
              dab: BrushDabSettings(size: 1, flow: flow, spacing: spacing, hardness: 1),
              stroke: BrushStrokeSettings(stabilization: 0, blendMode: blendMode),
              modulations: BrushModulations())
    }

    /// The largest alpha in a square of side `2 · reach + 1` about `(x, y)` — used where a probe point
    /// need not land on a dab centre, so the assertion is about how much ink the stroke put down near
    /// there rather than about where the walk happened to place a dab.
    private func maxAlpha(_ pixels: (bytes: [UInt8], width: Int, height: Int),
                          around x: Int, _ y: Int, reach: Int = 5) -> CGFloat {
        var worst: CGFloat = 0
        for dy in -reach...reach where (0..<pixels.height).contains(y + dy) {
            for dx in -reach...reach where (0..<pixels.width).contains(x + dx) {
                worst = max(worst, alpha(pixels, x: x + dx, y: y + dy))
            }
        }
        return worst
    }

    /// **The ruling, stated as a pixel fact: a stroke reaches its opacity at a crossing and no
    /// further.** BRUSH.md §2.11 — *"Opacity caps what the whole stroke can reach however often it
    /// crosses itself"*.
    ///
    /// The two operands are two pixels of **one** stroke: the point two passes covered and a point one
    /// pass covered. Under the ruling they are the same number, because the cap is applied once to the
    /// whole walk. Under the arithmetic this stage replaced they are 0.4 and `1 - 0.6² = 0.64`, and the
    /// third assertion names that number so a regression cannot pass by making both pixels wrong
    /// together — which comparing them alone would allow.
    func testAStrokeThatCrossesItselfReachesItsOpacityAndNoFurther() {
        let texture = RasterLayerTexture(size: Self.canvasSize)
        // Dense spacing and full flow, so one pass alone already saturates the buffer's coverage:
        // that is what makes "the crossing is capped" a statement about the cap rather than about
        // how much ink two passes happen to lay.
        BrushStamper.stampStroke(into: texture, samples: Self.crossingStroke(),
                                 brush: Self.flatBrush(flow: 1, spacing: 0.15), color: .black,
                                 brushSize: 8, brushOpacity: 0.4, random: DabRandom(seed: 7))
        guard let pixels = rgbaPixels(of: texture) else {
            return XCTFail("Could not read back the stamped texture")
        }
        let crossed = alpha(pixels, x: 32, y: 32)
        let single = alpha(pixels, x: 14, y: 32)
        XCTAssertEqual(single, 0.4, accuracy: 0.02, "one pass at 40% opacity reads 40%")
        XCTAssertEqual(crossed, single, accuracy: 0.02,
                       "the crossing must read exactly what a single pass reads — that is the cap")
        XCTAssertLessThan(crossed, 0.5,
                          "and it must not be 1 - 0.6² = 0.64, which is what stamping the cap into "
                          + "every dab produced before §12 stage 8")
    }

    /// **Build-up still works, and opacity scales the finished stroke rather than each stamp.** The
    /// owner's ruling: *"Pressure drives flow, not a per-dab ceiling. A light pass is faint; go over it
    /// again and it darkens, up to the stroke's opacity and no further."*
    ///
    /// Wide spacing and a low flow, so a single pass genuinely does not saturate and the crossing has
    /// somewhere to darken to. The second half is the sharper assertion: halving the stroke's opacity
    /// must halve **every** pixel by the same factor, because opacity multiplies a finished coverage
    /// map. Folding it into each dab instead does not scale uniformly — it would leave the crossing
    /// proportionally darker than the single pass — so this cannot pass under the arithmetic it
    /// replaced.
    func testFlowBuildsUpWhereAStrokeCrossesItselfAndOpacityScalesTheWhole() {
        func render(opacity: Double) -> (bytes: [UInt8], width: Int, height: Int)? {
            let texture = RasterLayerTexture(size: Self.canvasSize)
            BrushStamper.stampStroke(into: texture, samples: Self.crossingStroke(),
                                     brush: Self.flatBrush(flow: 0.3, spacing: 1.0), color: .black,
                                     brushSize: 8, brushOpacity: opacity, random: DabRandom(seed: 7))
            return rgbaPixels(of: texture)
        }
        guard let full = render(opacity: 1), let half = render(opacity: 0.5) else {
            return XCTFail("Could not read back the stamped textures")
        }
        let crossed = maxAlpha(full, around: 32, 32)
        let single = maxAlpha(full, around: 12, 32)
        XCTAssertGreaterThan(single, 0.2, "a single pass at flow 0.3 is faint but present")
        XCTAssertLessThan(single, 0.45, "…and one pass of a 30% flow is not a solid line")
        XCTAssertGreaterThan(crossed, single * 1.3,
                             "going over it again has to darken it — that is what flow is for")
        XCTAssertLessThanOrEqual(crossed, 1.0, "and nothing may exceed the stroke's own opacity")

        for (label, x) in [("the crossing", 32), ("a single pass", 12)] {
            XCTAssertEqual(maxAlpha(half, around: x, 32), maxAlpha(full, around: x, 32) / 2,
                           accuracy: 0.02,
                           "halving the stroke's opacity halves \(label) by the same factor: "
                           + "opacity scales a finished stroke, it is not a ceiling on a stamp")
        }
    }

    /// **A 50% eraser removes 50% wherever it goes, however often it crosses back over itself** — the
    /// owner's second ruling, on both tiers that erase.
    ///
    /// The `.full` tier is `stampStroke` with `isEraser`, which is what a vector cel replays and what
    /// the shape tool commits. The live tier is a `.subtractive` `StrokeScratch`, which is what the pen
    /// draws into on a raster layer and in the vector eraser's Mode 1; it is fed the dabs `stampStroke`
    /// itself would lay, `.normal`, exactly as `StrokeCanvasView.stampPath` feeds it.
    ///
    /// `1 - 0.5² = 0.75` removed — 25% of the ink left standing — is what punching each dab
    /// separately produced, and the assertions name it so a regression cannot pass by darkening both
    /// probes together.
    func testAnEraserAtHalfOpacityTakesAwayHalfOnBothTiers() {
        let eraser = Self.flatBrush(flow: 1, spacing: 0.15)
        let samples = Self.crossingStroke()

        func opaqueTexture() -> RasterLayerTexture {
            let texture = RasterLayerTexture(size: Self.canvasSize)
            texture.reset(to: Self.solidImage(.black, size: Self.canvasSize), strokeCount: 1)
            return texture
        }

        // The replay tier.
        let replayed = opaqueTexture()
        BrushStamper.stampStroke(into: replayed, samples: samples, brush: eraser, color: .black,
                                 brushSize: 8, brushOpacity: 0.5, isEraser: true,
                                 random: DabRandom(seed: 7))

        // The live tier: the same dabs, into the window the pen erases into.
        let committed = opaqueTexture()
        let scratch = StrokeScratch(canvasSize: Self.canvasSize,
                                    role: .subtractive(backdrop: committed.renderToUIImage()),
                                    opacity: 0.5)
        let walk = BrushStamper.bake(samples: samples, brush: eraser, color: .black, brushSize: 8,
                                     brushOpacity: 0.5, isEraser: true, random: DabRandom(seed: 7))
        XCTAssertEqual(walk.opacity, 0.5, "the bake carries the stroke's cap, not each dab's")
        XCTAssertEqual(walk.blendMode, .destinationOut, "…and the punch that cap is applied through")
        for dab in walk.dabs {
            guard case .round(let hardness) = dab.tip else { continue }
            scratch.stampCircle(at: dab.center, radius: dab.radius, color: dab.color,
                                alpha: dab.alpha, hardness: hardness, blendMode: dab.blendMode)
        }
        scratch.commit(into: committed)

        for (tier, texture) in [("the replay tier", replayed), ("the live tier", committed)] {
            guard let pixels = rgbaPixels(of: texture) else {
                return XCTFail("Could not read back \(tier)")
            }
            let crossed = alpha(pixels, x: 32, y: 32)
            let single = alpha(pixels, x: 14, y: 32)
            XCTAssertEqual(single, 0.5, accuracy: 0.02,
                           "\(tier): a 50% eraser leaves half the ink where it passed once")
            XCTAssertEqual(crossed, single, accuracy: 0.02,
                           "\(tier): and exactly the same half where it crossed back over itself")
            XCTAssertGreaterThan(crossed, 0.35,
                                 "\(tier): 0.25 is what punching every dab separately left — "
                                 + "1 - 0.5² removed rather than 0.5")
        }
    }

    /// **Nothing is clipped by the merge, under a brush that throws its dabs as far as this engine
    /// allows.** The group opens its buffer over the union of the rectangles its dabs actually
    /// painted, so this is the assertion that the union is right: heavy `size` and `scatter`
    /// modulation puts dabs well off the centreline and at widely varying widths, and the same walk
    /// drawn with no group at all must produce the same picture.
    ///
    /// The two operands are the shipped `stampStroke` and its own dabs replayed one at a time — the
    /// bake, which is `stampStroke` into a collector. So the walk, the random field and every dab's
    /// alpha are held identical by construction and the only difference between the arms is whether
    /// the merge happened. At opacity 1 under `.normal` the merge is source-over into a transparent
    /// buffer and then source-over onto the destination, which is associative, so the two agree; a
    /// bound that fell short would take a dab's edge — or a whole dab — off one side.
    func testAScatteringStrokeLosesNoInkToTheMerge() {
        var brush = Self.flatBrush(flow: 0.7, spacing: 0.3)
        brush.dab.scatter = 0.9
        brush.modulations = BrushModulations([BrushModulation(.size, .pressure, amount: -0.7),
                                              BrushModulation(.scatter, .pressure, amount: 0.5)])
        let samples = StrokeSamples((0..<12).map {
            VectorSample(x: 8 + CGFloat($0) * 4, y: 14 + CGFloat($0) * 3,
                         pressure: 0.12 + CGFloat($0) * 0.08)
        }, channels: .pressureOnly)

        let grouped = RasterLayerTexture(size: Self.canvasSize)
        BrushStamper.stampStroke(into: grouped, samples: samples, brush: brush, color: .black,
                                 brushSize: 14, brushOpacity: 1, random: DabRandom(seed: 4242))

        let direct = RasterLayerTexture(size: Self.canvasSize)
        let walk = BrushStamper.bake(samples: samples, brush: brush, color: .black, brushSize: 14,
                                     brushOpacity: 1, random: DabRandom(seed: 4242))
        XCTAssertGreaterThan(walk.dabs.count, 10, "Setup: there are dabs, at a range of widths")
        XCTAssertGreaterThan(Set(walk.dabs.map(\.radius)).count, 5,
                             "Setup: the size row is actually moving the dabs' widths")
        for dab in walk.dabs {
            guard case .round(let hardness) = dab.tip else { continue }
            direct.stampCircle(at: dab.center, radius: dab.radius, color: dab.color,
                               alpha: dab.alpha, hardness: hardness, blendMode: dab.blendMode)
        }

        assertPixelsMatch(grouped, direct,
                          "the merge must not clip a scattered dab that landed off the centreline")
    }

    /// **The clean-cut gate still refuses a brush that would not remove the ink outright**, which is
    /// the one guard §12 stage 8 could have turned into a tautology: it used to ask twice — once on
    /// `opacity · flow` and once on the matrix's own `opacity` output — and that second output is gone,
    /// so a guard left reading it would have been comparing a base that is now always 1.
    ///
    /// A false "clean cut" **deletes ink that should have faded**, which `supportsCleanCut`'s own doc
    /// names as the asymmetric direction. Mutation-tested: relaxing the surviving guard to
    /// `>= 0` makes the first two rows below pass, so this is looking at the product.
    func testTheCleanCutGateReadsTheMergedAlphaRatherThanADeletedOutput() {
        var solid = BrushLibrary.hardRound
        solid.dab.hardness = 1
        solid.dab.flow = 1
        solid.dab.scatter = 0
        solid.modulations = BrushModulations()

        XCTAssertTrue(VectorEraser.supportsCleanCut(brush: solid, opacity: 1, minPressure: 1),
                      "an opaque eraser at full flow removes the ink outright and may cut cleanly")

        var faint = solid
        faint.dab.flow = 0.8
        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: faint, opacity: 1, minPressure: 1),
                       "a brush laying 80% per stamp leaves ink behind — refuse the cut")

        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: solid, opacity: 0.5, minPressure: 1),
                       "and so does a full-flow brush the artist has set to half opacity")

        // The gate reads the *product*, so a stroke can fail on either factor and on both together.
        var pressureDriven = solid
        pressureDriven.dab.flow = 0
        pressureDriven.modulations = BrushModulations([.flowFromPressure(amount: 1)])
        XCTAssertTrue(VectorEraser.supportsCleanCut(brush: pressureDriven, opacity: 1, minPressure: 1),
                      "a `flow ← pressure` brush pressed hard reaches 1 and may cut")
        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: pressureDriven, opacity: 1, minPressure: 0.9),
                       "…and the same brush at the lightest pressure the gesture carried does not")
    }

    /// **A blend-mode stroke blends against what is under it once, not once per overlap.** BRUSH.md
    /// §2.11's other half: the mode travels on the stroke's merge, so a `.multiply` stroke that crosses
    /// itself is not darker at the crossing.
    ///
    /// Over an opaque mid grey, a `.multiply` stroke of the same grey lands `0.5 · 0.5` where it passed
    /// once. Multiplying per dab lands `0.5³` at a crossing, which is a different colour by 60 counts —
    /// so the third assertion names that number rather than only comparing the two probes, which a
    /// regression that darkened both would satisfy.
    ///
    /// The existing blend-mode tests are all one-dab or comparative (`VectorCanvas`' isolation rules
    /// compare a run against a run) and pin nothing about a stroke's overlap with itself.
    func testAMultiplyStrokeBlendsOnceWhereItCrossesItself() {
        let backdrop = UIColor(white: 0.5, alpha: 1)
        let texture = RasterLayerTexture(size: Self.canvasSize)
        texture.reset(to: Self.solidImage(backdrop, size: Self.canvasSize), strokeCount: 1)
        BrushStamper.stampStroke(into: texture, samples: Self.crossingStroke(),
                                 brush: Self.flatBrush(flow: 1, spacing: 0.15, blendMode: .multiply),
                                 color: UIColor(white: 0.5, alpha: 1),
                                 brushSize: 8, brushOpacity: 1, random: DabRandom(seed: 7))
        guard let pixels = rgbaPixels(of: texture) else {
            return XCTFail("Could not read back the stamped texture")
        }
        func red(_ x: Int, _ y: Int) -> Int { Int(pixels.bytes[(y * pixels.width + x) * 4]) }
        let crossed = red(32, 32), single = red(14, 32), untouched = red(2, 2)

        XCTAssertEqual(untouched, 128, accuracy: 2, "Setup: the backdrop is a mid grey")
        XCTAssertEqual(single, 64, accuracy: 3, "one pass of a 50% multiply over 50% grey is 25%")
        XCTAssertEqual(crossed, single, accuracy: 3,
                       "the crossing must be the same colour — the mode belongs to the stroke")
        XCTAssertGreaterThan(crossed, 45,
                             "and not 0.5³ = 32, which is what multiplying once per dab produced")
    }

    /// A solid rectangle of `color`, for the tests above that need something to erase or to blend
    /// against. `RasterLayerTexture` has no fill primitive of its own — it stamps dabs — so the
    /// backdrop arrives the way an undo patch does, through `reset(to:strokeCount:)`.
    private static func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Whole-texture comparison at a tolerance of `tolerance` on every byte — the form the scratch's
    /// commit claims have to take, since "looks the same" is exactly what a half-pixel offset or a
    /// re-composited backdrop would also do.
    ///
    /// **Two bytes, and not zero, and the reason is quantisation rather than slack.** Compositing
    /// into an 8-bit scratch and then compositing that over the layer rounds twice where stamping
    /// straight into the layer rounds once, so an anti-aliased dab edge can land a step either way.
    /// It is bounded and it does not accumulate with stroke length — the dabs are composited against
    /// each other identically in both arrangements. A geometry mistake is not bounded like that: a
    /// window off by one pixel, or an origin taken before the clamp, moves a dab edge by a whole
    /// dab's contrast and fails this at any tolerance worth the name.
    private func assertPixelsMatch(_ lhs: RasterLayerTexture, _ rhs: RasterLayerTexture,
                                   tolerance: Int = 2, _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let a = rgbaPixels(of: lhs), let b = rgbaPixels(of: rhs) else {
            return XCTFail("Could not read back the textures", file: file, line: line)
        }
        XCTAssertEqual(a.width, b.width, file: file, line: line)
        XCTAssertEqual(a.height, b.height, file: file, line: line)
        guard a.bytes.count == b.bytes.count else {
            return XCTFail(message, file: file, line: line)
        }
        var offending = 0
        var worst = 0
        for i in 0..<a.bytes.count {
            let delta = abs(Int(a.bytes[i]) - Int(b.bytes[i]))
            worst = max(worst, delta)
            if delta > tolerance { offending += 1 }
        }
        XCTAssertEqual(offending, 0,
                       message + " — \(offending) bytes past a tolerance of \(tolerance), worst by \(worst)",
                       file: file, line: line)
    }
}
