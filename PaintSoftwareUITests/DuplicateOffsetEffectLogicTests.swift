import XCTest
import UIKit

/// TODO (61) stage 6's Duplicate Offset, headlessly — TRANSFORM_LAYER.md §3.4 and §8 row 6.
///
/// **Every number a test compares against is computed inside the test from the fixture**, never
/// eyeballed from a render: the rim and intersection of a disc against its own copy slid half a
/// radius are counted pixel by pixel under the same centre rule that drew the disc, and then checked
/// against the two circles' continuous areas; the seven blend formulas that reached the CPU only
/// through `CGBlendMode` until this stage are pinned to W3C's own arithmetic; the box's rotation is
/// pinned to `CGAffineTransform.rotated(by:)`'s direction by a drawing whose copy lands on one dot and
/// not the other.
///
/// The two backends are held to one channel step per blend mode and per region, on a whole frame and
/// on one strip window of one — `EffectParityLogicTests`' gate, restated per mode because the mode is
/// a switch inside the kernel and a parity sweep at one mode says nothing about the other twenty-four.
///
/// `DuplicateOffsetUITests` drives the same effect from an empty document and reads what the canvas
/// draws; `StripedCompositeLogicTests` pins the apron under the strip driver itself, both backends.
@MainActor
final class DuplicateOffsetEffectLogicTests: XCTestCase {

    private static let side = 64

    // MARK: - Fixtures

    /// `EffectParityLogicTests.spectrumBytes`: every pixel a different (colour, alpha) combination,
    /// with a fully transparent band and a fully opaque one — and, between them, **soft** alpha,
    /// which is what the identity claim is about.
    private func spectrumBytes(width: Int = DuplicateOffsetEffectLogicTests.side,
                               height: Int = DuplicateOffsetEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let colour = [x * 4, y * 4, ((x + y) * 2) % 256]
                let alpha = min(255, (x / 8) * 36 + (y / 16) * 3)
                let offset = (x + y * width) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    /// An opaque disc of `radius` about the buffer's centre, drawn by the pixel-centre rule — a pixel
    /// is in the disc when its centre is within `radius` of the buffer's centre — so the same rule can
    /// be re-applied in a test to say which pixels a slid copy covers. Binary alpha, deliberately: it
    /// is what makes the two regions exact pixel sets rather than blends.
    private func disc(radius: Double, colour: (UInt8, UInt8, UInt8) = (0, 0, 0)) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for y in 0..<Self.side {
            for x in 0..<Self.side where inDisc(x: x, y: y, radius: radius) {
                let offset = (x + y * Self.side) * 4
                bytes[offset] = colour.0; bytes[offset + 1] = colour.1; bytes[offset + 2] = colour.2
                bytes[offset + 3] = 255
            }
        }
        return bytes
    }

    private func inDisc(x: Int, y: Int, radius: Double, shiftedBy shift: (Double, Double) = (0, 0)) -> Bool {
        let centre = Double(Self.side) / 2
        let dx = Double(x) + 0.5 - centre - shift.0, dy = Double(y) + 0.5 - centre - shift.1
        return dx * dx + dy * dy <= radius * radius
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8],
                     width: Int = DuplicateOffsetEffectLogicTests.side,
                     height: Int = DuplicateOffsetEffectLogicTests.side) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: width, height: height)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let offset = (x + y * Self.side) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    private func dup(_ configure: (inout Effect.DuplicateOffset) -> Void) -> Effect {
        var params = Effect.DuplicateOffset()
        configure(&params)
        return .duplicateOffset(params)
    }

    private let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)

    /// Whether the pixel came out as the effect's flat red at full opacity over black ink.
    private func isPaintedRed(_ p: [Int]) -> Bool { p[0] >= 250 && p[1] <= 5 && p[2] <= 5 && p[3] == 255 }

    // MARK: - The identity, and coverage

    /// **The type's default paints nothing, on soft ink, byte for byte** — `Effect.DuplicateOffset`'s
    /// doc, and the reason the regions are `min`/`max` rather than products. The spectrum fixture is
    /// mostly partial alpha, which is exactly where the product formula would have painted a rim:
    /// `orig.a · (1 − dup.a)` with `dup == orig` is `a(1 − a)`, positive on every soft pixel, so the
    /// old formula turns this fixture red (in both senses) — MEASURED by mutation, 2026-09-11: with
    /// the rim's `max(oa − da, 0)` replaced by `oa * (1 − da)`, this differs at the first soft pixel.
    func testTheIdentityPaintsNothingOnSoftInk() {
        let bytes = spectrumBytes()
        let identity = dup { $0.color = red }
        XCTAssertTrue(Effect.DuplicateOffset().isIdentity, "Premise: the type's default is the identity")
        XCTAssertEqual(cpu(identity, bytes), bytes, "Zero offset, unit scale, rim: nothing to paint")
        // An identity with every non-box knob moved is still one: the region is empty whatever the
        // colour, mode or opacity says.
        XCTAssertEqual(cpu(dup { $0.color = red; $0.blendMode = .difference; $0.opacity = 1 }, bytes), bytes)
        // And the fixture is not vacuous: the same box in the other region paints the whole drawing.
        XCTAssertNotEqual(cpu(dup { $0.color = red; $0.region = .intersection }, bytes), bytes,
                          "At rest the intersection is the whole drawing")
        // Opacity 0 is the identity in either region.
        XCTAssertEqual(cpu(dup { $0.color = red; $0.region = .intersection; $0.opacity = 0 }, bytes), bytes)
    }

    func testTheIdentityPaintsNothingOnTheGPUToo() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        guard let gpu = engine.apply(dup { $0.color = red }, to: bytes, width: Self.side, height: Self.side)
        else { return XCTFail("The GPU declined the identity") }
        XCTAssertLessThanOrEqual(maxChannelDelta(gpu, bytes), 1, "The identity on the GPU, to a channel step")
    }

    /// **Alpha is written back byte for byte in both regions, whatever the box does** — the claim
    /// `reshapesCoverage == false` makes and the one `testNoEffectChangesAlpha` sweeps; stated here
    /// on the disc as well, where a leaked alpha would be a rim that grew past the drawing.
    func testNeitherRegionChangesCoverage() {
        for (name, effect) in [
            ("rim", dup { $0.offsetX = 10; $0.scaleX = 1.4; $0.rotationDegrees = 30; $0.color = red }),
            ("intersection", dup { $0.offsetY = -7; $0.region = .intersection; $0.color = red; $0.blendMode = .screen }),
        ] {
            XCTAssertFalse(effect.reshapesCoverage, "\(name) is a grade")
            for bytes in [disc(radius: 20), spectrumBytes()] {
                let out = cpu(effect, bytes)
                let differing = stride(from: 3, to: bytes.count, by: 4).first { out[$0] != bytes[$0] }
                XCTAssertNil(differing, "\(name) changed alpha at byte \(differing ?? -1)")
            }
        }
    }

    // MARK: - Rim and intersection over a known shape

    /// **A disc of radius 20 against its own copy slid half a radius: the rim and the intersection
    /// have the areas two circles say they have.** The copy is slid by an integer, so the bilinear
    /// tap is exact and each region is an exact pixel set: rim is the disc's pixels whose centres are
    /// *not* inside the shifted disc, intersection those that are — counted here by re-applying the
    /// centre rule the fixture was drawn with. Then, as a check on the geometry rather than on the
    /// code, both counts are held to the two circles' continuous areas within a perimeter's worth of
    /// discretisation: for `d = R/2`, `A∩ = 2R²·acos(d/2R) − (d/2)·√(4R² − d²)` and `A rim = πR² − A∩`.
    ///
    /// Red at full opacity in Normal over black ink, so "painted" is a byte test and the two regions
    /// partition the disc: every disc pixel is red under exactly one of the two.
    func testRimAndIntersectionOverADiscSlidHalfARadiusHaveTheHandComputedAreas() {
        let radius = 20.0, shift = radius / 2
        let bytes = disc(radius: radius)
        let rim = cpu(dup { $0.offsetX = shift; $0.color = red }, bytes)
        let intersection = cpu(dup { $0.offsetX = shift; $0.region = .intersection; $0.color = red }, bytes)

        var expectedRim = 0, expectedIntersection = 0, paintedRim = 0, paintedIntersection = 0, outside = 0
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let inOriginal = inDisc(x: x, y: y, radius: radius)
                let inCopy = inDisc(x: x, y: y, radius: radius, shiftedBy: (shift, 0))
                if inOriginal && !inCopy { expectedRim += 1 }
                if inOriginal && inCopy { expectedIntersection += 1 }
                if isPaintedRed(pixel(rim, x, y)) { paintedRim += 1 }
                if isPaintedRed(pixel(intersection, x, y)) { paintedIntersection += 1 }
                if !inOriginal, pixel(rim, x, y)[3] != 0 || pixel(intersection, x, y)[3] != 0 { outside += 1 }
                if inOriginal {
                    XCTAssertNotEqual(isPaintedRed(pixel(rim, x, y)), isPaintedRed(pixel(intersection, x, y)),
                                      "(\(x), \(y)) is in exactly one region")
                }
            }
        }
        XCTAssertEqual(paintedRim, expectedRim, "The rim is the disc minus the slid copy, pixel for pixel")
        XCTAssertEqual(paintedIntersection, expectedIntersection, "The intersection is the disc and the slid copy")
        XCTAssertEqual(outside, 0, "Nothing is painted outside the drawing — §2 ruling 14")

        // The geometry, continuous: two circles of radius R whose centres are R/2 apart.
        let d = shift
        let lens = 2 * radius * radius * acos(d / (2 * radius)) - (d / 2) * (4 * radius * radius - d * d).squareRoot()
        let discArea = Double.pi * radius * radius
        let perimeter = 2 * Double.pi * radius
        XCTAssertEqual(Double(paintedIntersection), lens, accuracy: perimeter / 2,
                       "The lens of two circles half a radius apart: \(lens)")
        XCTAssertEqual(Double(paintedRim), discArea - lens, accuracy: perimeter / 2,
                       "The disc less the lens: \(discArea - lens)")
        XCTAssertGreaterThan(paintedRim, 300, "Sanity: a rim a third of the disc, not a sliver")
        XCTAssertGreaterThan(paintedIntersection, 700, "Sanity: an intersection of two thirds")
    }

    /// **The box's turn is `CGAffineTransform.rotated(by:)`'s — clockwise on screen — which is what
    /// the Move box the artist drags means by a positive rotation.** Two dots, one to the right of
    /// the centre and one below it: a quarter turn clockwise carries the right dot's copy onto the
    /// lower dot, so under Intersection the lower dot is painted and the right one is not; a quarter
    /// turn the other way swaps them. A sign error in `dupSin` swaps them too, which is what this
    /// pins (MEASURED by mutation, 2026-09-11: with the resample's `−sin·q.x` made `+sin·q.x`, the
    /// two assertions on the first backend reverse).
    func testAPositiveRotationTurnsTheCopyClockwiseOnScreen() throws {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        let centre = Self.side / 2
        func dot(_ x: Int, _ y: Int) {
            for dy in -1...1 { for dx in -1...1 {
                let offset = ((x + dx) + (y + dy) * Self.side) * 4
                bytes[offset + 3] = 255
            } }
        }
        let right = (centre + 12, centre), below = (centre, centre + 12)
        dot(right.0, right.1); dot(below.0, below.1)

        let clockwise = cpu(dup { $0.rotationDegrees = 90; $0.region = .intersection; $0.color = red }, bytes)
        XCTAssertTrue(isPaintedRed(pixel(clockwise, below.0, below.1)),
                      "+90°: the right dot's copy lands on the lower dot, so the lower dot is intersection")
        XCTAssertFalse(isPaintedRed(pixel(clockwise, right.0, right.1)),
                       "…and the right dot's own copy has gone below it, so the right dot is not")

        let anticlockwise = cpu(dup { $0.rotationDegrees = -90; $0.region = .intersection; $0.color = red }, bytes)
        XCTAssertTrue(isPaintedRed(pixel(anticlockwise, right.0, right.1)), "−90°: the other way round")
        XCTAssertFalse(isPaintedRed(pixel(anticlockwise, below.0, below.1)))

        // And the same on the GPU, so the direction is a fact about both kernels.
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared,
              let gpu = engine.apply(dup { $0.rotationDegrees = 90; $0.region = .intersection; $0.color = red },
                                     to: bytes, width: Self.side, height: Self.side)
        else { return XCTFail("The GPU declined the turn") }
        XCTAssertTrue(isPaintedRed(pixel(gpu, below.0, below.1)), "The shader turns the same way")
        XCTAssertFalse(isPaintedRed(pixel(gpu, right.0, right.1)))
    }

    /// A scale about the centre: a copy at half size of a disc of radius 20 is a disc of radius 10,
    /// so the intersection is the inner disc and the rim the annulus — counted by the centre rule
    /// again. A scale is a box gesture the artist makes by dragging a corner, and this is what it
    /// draws.
    func testAHalfSizeCopyMakesTheRimAnAnnulus() {
        let bytes = disc(radius: 20)
        let rim = cpu(dup { $0.scaleX = 0.5; $0.scaleY = 0.5; $0.color = red }, bytes)
        var expectedRim = 0, paintedRim = 0
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                if inDisc(x: x, y: y, radius: 20) && !inDisc(x: x, y: y, radius: 10) { expectedRim += 1 }
                if isPaintedRed(pixel(rim, x, y)) { paintedRim += 1 }
            }
        }
        // The half-size copy's edge is resampled, not drawn by the centre rule, so a ring of pixels
        // along the inner circle is partly painted rather than fully; a circle of radius 10 is ~63
        // pixels long, and that is the tolerance.
        XCTAssertEqual(Double(paintedRim), Double(expectedRim), accuracy: 63,
                       "The rim of a half-size copy is the annulus between radius 10 and 20")
        XCTAssertGreaterThan(paintedRim, 800, "Sanity: three quarters of the disc")
    }

    // MARK: - The blend, per mode

    /// **The seven modes the CPU reached only through `CGBlendMode` until this stage, against W3C
    /// Compositing Level 1 by hand** — `BlendMode.blendUnpremultiplied`'s new arms. Each value is the
    /// spec's formula evaluated on paper at a point where the branches differ: Hard Light and
    /// Overlay each on both sides of mid-grey, and Overlay with the operands the spec swaps.
    func testTheSevenCoreGraphicsModesMatchTheSpecByHand() {
        func blend(_ mode: BlendMode, _ cb: Float, _ cs: Float) -> Float {
            mode.blendUnpremultiplied(backdrop: SIMD3<Float>(repeating: cb), source: SIMD3<Float>(repeating: cs)).x
        }
        XCTAssertEqual(blend(.multiply, 0.5, 0.5), 0.25, accuracy: 1e-6)
        XCTAssertEqual(blend(.screen, 0.5, 0.5), 0.75, accuracy: 1e-6, "cb + cs − cb·cs")
        XCTAssertEqual(blend(.darken, 0.3, 0.8), 0.3, accuracy: 1e-6)
        XCTAssertEqual(blend(.lighten, 0.3, 0.8), 0.8, accuracy: 1e-6)
        XCTAssertEqual(blend(.difference, 0.3, 0.8), 0.5, accuracy: 1e-6)
        // Hard Light: Multiply(cb, 2cs) below mid-grey, Screen(cb, 2cs − 1) above.
        XCTAssertEqual(blend(.hardLight, 0.5, 0.25), 0.25, accuracy: 1e-6, "0.5 · (2 · 0.25)")
        XCTAssertEqual(blend(.hardLight, 0.5, 0.75), 0.75, accuracy: 1e-6, "Screen(0.5, 0.5)")
        // Overlay is Hard Light with the operands swapped: the *backdrop* picks the branch.
        XCTAssertEqual(blend(.overlay, 0.25, 0.5), 0.25, accuracy: 1e-6, "cb ≤ 0.5: Multiply(cs, 2cb) = 0.5 · 0.5")
        XCTAssertEqual(blend(.overlay, 0.75, 0.5), 0.75, accuracy: 1e-6, "cb > 0.5: Screen(cs, 2cb − 1) = Screen(0.5, 0.5)")
        // Normal is the source, and Clip to Below composites as Normal everywhere.
        XCTAssertEqual(blend(.normal, 0.3, 0.8), 0.8, accuracy: 1e-6)
        XCTAssertEqual(blend(.clipToBelow, 0.3, 0.8), 0.8, accuracy: 1e-6)
        // And a non-separable one still goes through the triple: Luminosity of grey onto grey is the
        // source's grey.
        XCTAssertEqual(blend(.luminosity, 0.3, 0.8), 0.8, accuracy: 1e-5)
    }

    /// **Every blend mode, both regions, both backends, over 4096 (colour, alpha) pairs**, at one
    /// channel step — the gate `EffectParityLogicTests` holds every grade to. Per mode because the
    /// mode is a `switch` inside both combines and a sweep at Normal proves nothing about Vivid
    /// Light. A slid, scaled, turned box, so the resample pass is exercised on both sides as well.
    ///
    /// MEASURED 2026-09-11 (simulator, this fixture): the largest delta over the fifty rows was 1.
    func testEveryBlendModeAndBothRegionsAgreeBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let colour = CodableColor(red: 0.8, green: 0.35, blue: 0.6, alpha: 1)
        var worst = 0
        for mode in BlendMode.allCases {
            for region in Effect.DuplicateOffset.Region.allCases {
                let effect = dup {
                    $0.offsetX = 5.5; $0.offsetY = -3.25; $0.scaleX = 1.2; $0.scaleY = 0.85
                    $0.rotationDegrees = 17; $0.region = region; $0.blendMode = mode
                    $0.opacity = 0.8; $0.color = colour
                }
                guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                    XCTFail("The GPU declined \(mode.rawValue)/\(region.rawValue)"); continue
                }
                let reference = cpu(effect, bytes)
                let delta = maxChannelDelta(gpu, reference)
                worst = max(worst, delta)
                XCTAssertLessThanOrEqual(delta, 1, "\(mode.rawValue) in \(region.rawValue) differs by \(delta)")
                XCTAssertNotEqual(reference, bytes, "The fixture is not vacuous for \(mode.rawValue)")
            }
        }
        XCTContext.runActivity(named: "[duplicate offset] Metal-vs-Swift max channel delta over every mode: \(worst)") { _ in }
    }

    /// **Both backends stamp the same frame onto one strip window** — `CRTScreenEffectLogicTests`'
    /// window test for the box: a 64×64 buffer that is rows 16…79 of a 64×128 frame. The box is
    /// about the *frame's* centre (row 64), and a strip that centred it on itself (row 48) would
    /// turn and scale the copy about the wrong point; both kernels read `originX/originY` and
    /// `frameWidth/frameHeight`, and the two have to agree about it as well as about the arithmetic.
    /// **Not the middle band**, deliberately: rows 32…95 of that frame have the frame's own centre,
    /// and a box about a centre cannot tell that window from the whole — the first draft of this
    /// test used it and its non-vacuity check went red for exactly that reason.
    func testBothBackendsStampTheSameFrameOntoAStripWindow() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let effect = dup { $0.offsetX = 6; $0.offsetY = -4; $0.scaleX = 1.1; $0.rotationDegrees = 25; $0.color = red }
        let origin: (x: UInt32, y: UInt32) = (0, 16)
        let frame: (width: UInt32, height: UInt32) = (64, 128)
        guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side,
                                     origin: origin, frameSize: frame) else {
            return XCTFail("The GPU declined the windowed box")
        }
        let reference = EffectReference.apply(effect, to: bytes, width: Self.side, height: Self.side,
                                              origin: origin, frameSize: frame)
        XCTAssertLessThanOrEqual(maxChannelDelta(gpu, reference), 1, "The two backends stamp the window differently")
        XCTAssertNotEqual(reference, cpu(effect, bytes),
                          "A strip must be windowed onto the frame, not treated as a smaller frame")
    }

    /// **A strip of the effect is exactly the rows of the whole, given the apron's rows** — the CPU
    /// half of the driver pin in `StripedCompositeLogicTests`, at the kernel: rows 16…47 of a 64-row
    /// frame composited as a window whose buffer holds rows 16 − 21 … 47 + 21 read, in their core,
    /// byte for byte what the whole frame reads there. That is the claim `verticalKernelRadius`
    /// makes: a copy slid 20 rows needs 21 rows of context.
    func testAStripWithItsApronIsTheRowsOfTheWhole() {
        let width = Self.side, frameHeight = 64, top = 16, coreRows = 32
        let frameBytes = spectrumBytes(width: width, height: frameHeight)
        let effect = dup { $0.offsetY = 20; $0.offsetX = 3; $0.region = .intersection; $0.color = red }
        let apron = effect.verticalKernelRadius(frameSize: (width, frameHeight))
        XCTAssertEqual(apron, 21, "Premise: twenty rows and the bilinear row")
        let whole = EffectReference.apply(effect, to: frameBytes, width: width, height: frameHeight)

        let bufferTop = max(0, top - apron), bufferBottom = min(frameHeight, top + coreRows + apron)
        let stripBytes = Array(frameBytes[(bufferTop * width * 4)..<(bufferBottom * width * 4)])
        let strip = EffectReference.apply(effect, to: stripBytes, width: width, height: bufferBottom - bufferTop,
                                          origin: (0, UInt32(bufferTop)),
                                          frameSize: (UInt32(width), UInt32(frameHeight)))
        let coreOfStrip = Array(strip[((top - bufferTop) * width * 4)..<((top - bufferTop + coreRows) * width * 4)])
        let coreOfWhole = Array(whole[(top * width * 4)..<((top + coreRows) * width * 4)])
        XCTAssertEqual(coreOfStrip, coreOfWhole, "The strip's core is the frame's own rows, apron included")
        // Without the apron the copy's source is missing from the buffer and the core differs.
        let bare = Array(frameBytes[(top * width * 4)..<((top + coreRows) * width * 4)])
        let bareStrip = EffectReference.apply(effect, to: bare, width: width, height: coreRows,
                                              origin: (0, UInt32(top)),
                                              frameSize: (UInt32(width), UInt32(frameHeight)))
        XCTAssertNotEqual(bareStrip, coreOfWhole, "…and a strip with no apron is not")
    }

    // MARK: - What the kernels are handed

    /// `params` resolves the box once for both backends: the offset on the shared displacement pair,
    /// the reciprocal scales floored at `minimumScale` with the sign kept, cosine and sine of the
    /// turn, the region's code, the mode's `shaderCode` with Clip to Below composited as Normal, the
    /// opacity clamped on `mix`, the colour on the trailing triple.
    func testParamsResolveTheBoxOnceForBothBackends() {
        let p = dup {
            $0.offsetX = 12; $0.offsetY = -7; $0.scaleX = 2; $0.scaleY = -0.5; $0.rotationDegrees = 90
            $0.region = .intersection; $0.blendMode = .vividLight; $0.opacity = 1.7
            $0.color = CodableColor(red: 0.2, green: 1.4, blue: -0.3, alpha: 0.5)
        }.params
        XCTAssertEqual(p.offsetX, 12); XCTAssertEqual(p.offsetY, -7)
        XCTAssertEqual(p.dupInverseScaleX, 0.5); XCTAssertEqual(p.dupInverseScaleY, -2)
        XCTAssertEqual(p.dupCos, 0, accuracy: 1e-6); XCTAssertEqual(p.dupSin, 1, accuracy: 1e-6)
        XCTAssertEqual(p.dupRegion, 1)
        XCTAssertEqual(p.dupBlendMode, BlendMode.vividLight.shaderCode)
        XCTAssertEqual(p.mix, 1, "Opacity is clamped to its slider")
        XCTAssertEqual([p.colorR, p.colorG, p.colorB], [0.2, 1, 0], "Colour clamped, alpha ignored")

        let zero = dup { $0.scaleX = 0; $0.scaleY = -0 }.params
        XCTAssertEqual(zero.dupInverseScaleX, Float(1 / Effect.DuplicateOffset.minimumScale),
                       "A zero scale is floored, not divided by")
        XCTAssertEqual(dup { $0.scaleX = -1e-9 }.params.dupInverseScaleX, Float(-1 / Effect.DuplicateOffset.minimumScale),
                       "…with its sign kept, so a mirrored copy stays mirrored")
        XCTAssertEqual(dup { $0.blendMode = .clipToBelow }.params.dupBlendMode, 0, "Clip to Below composites as Normal")
        XCTAssertEqual(dup { $0.offsetX = .nan; $0.rotationDegrees = .infinity }.params.offsetX, 0,
                       "A non-finite knob is its identity")

        let passes = dup { $0.offsetX = 4 }.passes
        XCTAssertEqual(passes.count, 2, "Two passes: the resample, then the combine")
        XCTAssertEqual(passes[0].kind, 15); XCTAssertEqual(passes[1].kind, 16)
        XCTAssertEqual(passes[0].params, passes[1].params, "One parameter block serves both")
        XCTAssertEqual(dup { _ in }.input, .ink, "Fixed to the ink, like Outline")
        XCTAssertTrue(dup { _ in }.readsAbsolutePosition)
    }

    // MARK: - Persistence

    /// The effect survives a JSON round trip with every one of its nine fields, and a document
    /// written as the bare kind — or with a blend mode this build does not know — decodes to the
    /// identity rather than failing.
    func testTheEffectSurvivesAJSONRoundTripAndAnOldDocumentDecodesToTheIdentity() throws {
        let effect = dup {
            $0.offsetX = -8.5; $0.offsetY = 8; $0.scaleX = 1.25; $0.scaleY = 0.75; $0.rotationDegrees = -33
            $0.region = .intersection; $0.blendMode = .softLight; $0.opacity = 0.4
            $0.color = CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        }
        let data = try JSONEncoder().encode(effect)
        XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), effect)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"duplicateOffset\""), "Tagged by a stable name: \(json)")
        XCTAssertTrue(json.contains("\"region\":\"intersection\"") && json.contains("\"blendMode\":\"softLight\""),
                      "The region and the mode are written by their raw names: \(json)")

        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"duplicateOffset"}"#.utf8))
        XCTAssertEqual(bare, .duplicateOffset(Effect.DuplicateOffset()), "No params: the identity")
        let partial = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"duplicateOffset","params":{"offsetX":3}}"#.utf8))
        XCTAssertEqual(partial, .duplicateOffset(Effect.DuplicateOffset(offsetX: 3)), "Missing keys take their defaults")
    }

    // MARK: - The box as a writer

    private func gradedManager(_ effect: Effect) -> (CanvasManager, KeyframeTarget, Int) {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 16, y: 16, width: 32, height: 32)))
        manager.addValueLayer(effect: effect)
        let index = manager.layers.count - 1
        manager.currentLayerIndex = index
        return (manager, .layer(id: manager.layers[index].id), index)
    }

    private func stored(_ manager: CanvasManager, _ index: Int) -> Effect.DuplicateOffset? {
        guard case .duplicateOffset(let p)? = manager.layers[index].layerEffect else { return nil }
        return p
    }

    /// **The box comes up at the copy's current pose, the drag previews live, Done writes the five
    /// scalars as one step, and one undo restores all five** — §8 row 6's "the box commit writes the
    /// five scalars". The lift is read straight off the stored effect; the drag is
    /// `updateFloatingPose`, the overlay's own entry; the preview is checked on the *resolved* grade
    /// before Done, because that is what the render draws while the finger is down.
    func testTheBoxCommitWritesTheFiveScalarsAndOneUndoRestoresThem() {
        let (manager, target, index) = gradedManager(dup {
            $0.offsetX = 10; $0.offsetY = 20; $0.scaleX = 2; $0.scaleY = 0.5; $0.rotationDegrees = 45; $0.color = red
        })
        let steps = manager.history.undoStack.count

        XCTAssertTrue(manager.beginEffectBoxMove(for: target), "The box comes up on a Duplicate Offset")
        guard let piece = manager.floatingPiece else { return XCTFail("No piece floated") }
        XCTAssertEqual(piece.kind, .effectBox)
        XCTAssertEqual(piece.transform.position, CGPoint(x: 32 + 10, y: 32 + 20), "At the copy's centre")
        XCTAssertEqual(piece.transform.scaleX, 2); XCTAssertEqual(piece.transform.scaleY, 0.5)
        XCTAssertEqual(Double(piece.transform.rotation), 45 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(manager.history.undoStack.count, steps, "Raising the box records nothing")

        // The drag: the overlay writes a whole transform per tick.
        var dragged = piece.transform
        dragged.position = CGPoint(x: 32 - 6, y: 32 + 3)
        dragged.scaleX = 1.5; dragged.scaleY = 1.25; dragged.rotation = -0.3
        manager.updateFloatingPose(transform: dragged, distortQuad: nil)
        guard case .duplicateOffset(let live)? = manager.resolvedEffect(of: target, atFrame: manager.currentFrame)
        else { return XCTFail("The grade is gone") }
        XCTAssertEqual(live.offsetX, -6, accuracy: 1e-9, "The preview writes where the render reads")
        XCTAssertEqual(live.offsetY, 3, accuracy: 1e-9)
        XCTAssertEqual(live.scaleX, 1.5, accuracy: 1e-9); XCTAssertEqual(live.scaleY, 1.25, accuracy: 1e-9)
        XCTAssertEqual(live.rotationDegrees, -0.3 * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(manager.history.undoStack.count, steps, "…and records no step per tick")

        XCTAssertTrue(manager.commitAnyFloatingPiece(), "Done")
        XCTAssertNil(manager.floatingPiece)
        guard let after = stored(manager, index) else { return XCTFail("The grade is gone") }
        XCTAssertEqual(after.offsetX, -6, accuracy: 1e-9); XCTAssertEqual(after.offsetY, 3, accuracy: 1e-9)
        XCTAssertEqual(after.scaleX, 1.5, accuracy: 1e-9); XCTAssertEqual(after.scaleY, 1.25, accuracy: 1e-9)
        XCTAssertEqual(after.rotationDegrees, -0.3 * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(after.color, red, "The knobs the box does not write are untouched")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "One step for the whole drag")
        XCTAssertEqual(manager.history.undoStack.last?.label, .valueLayerEffect)

        manager.undo()
        guard let restored = stored(manager, index) else { return XCTFail("The grade is gone") }
        XCTAssertEqual(restored, Effect.DuplicateOffset(offsetX: 10, offsetY: 20, scaleX: 2, scaleY: 0.5,
                                                        rotationDegrees: 45, color: red),
                       "One undo puts all five back where the drag started — not where the preview left them")
    }

    /// A box that ended where it began writes nothing at all — the raster arm's rule, reached by
    /// comparing scalars. And Mirror is a negative scale: the bar's button flips the box, and the
    /// commit reads the sign back.
    func testAnUnmovedBoxWritesNoStepAndMirrorIsANegativeScale() {
        let (manager, target, index) = gradedManager(dup { $0.offsetX = 5; $0.color = red })
        let steps = manager.history.undoStack.count
        XCTAssertTrue(manager.beginEffectBoxMove(for: target))
        manager.commitAnyFloatingPiece()
        XCTAssertEqual(manager.history.undoStack.count, steps, "Nothing moved, nothing written")
        XCTAssertEqual(stored(manager, index)?.offsetX, 5)

        XCTAssertTrue(manager.beginEffectBoxMove(for: target))
        manager.mirrorFloating(horizontal: true)
        XCTAssertEqual(stored(manager, index)?.scaleX, -1, "The preview shows the mirror")
        manager.commitAnyFloatingPiece()
        XCTAssertEqual(stored(manager, index)?.scaleX, -1, "…and the commit keeps it")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1)

        // A mirrored copy comes back up mirrored: positive scale plus the flip bit.
        XCTAssertTrue(manager.beginEffectBoxMove(for: target))
        XCTAssertEqual(manager.floatingPiece?.transform.scaleX, 1)
        XCTAssertEqual(manager.floatingPiece?.transform.flipH, true)
        manager.commitAnyFloatingPiece()
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "Re-raising and committing unmoved writes nothing")
    }

    /// **The box refuses a frame the layer's bar does not cover and says which frame** — stage 1's
    /// "only here" reached from the Adjust Box row; and it refuses a layer that is not grading a
    /// Duplicate Offset at all, silently, because there is no row to have tapped.
    func testTheBoxIsRefusedOutsideTheLayersBarAndSaysSo() {
        let (manager, target, index) = gradedManager(dup { $0.offsetX = 5 })
        CanvasFixture.setCelLayout(manager, layerIndex: index, [(0, 4)])
        manager.currentFrame = 8
        XCTAssertNil(manager.activeCelIndex(inLayer: index, atFrame: 8), "Premise: no block at frame 8")
        let steps = manager.history.undoStack.count
        XCTAssertFalse(manager.beginEffectBoxMove(for: target), "No box past the bar")
        XCTAssertNil(manager.floatingPiece)
        XCTAssertEqual(manager.notice?.code, "effectBoxOutsideBlock", "…and it is said, not swallowed")
        XCTAssertTrue(manager.notice?.message.contains("Frame 9") == true,
                      "The sentence names the frame in the ruler's numbering: \(manager.notice?.message ?? "nil")")
        XCTAssertEqual(manager.history.undoStack.count, steps)

        manager.currentFrame = 2
        XCTAssertTrue(manager.beginEffectBoxMove(for: target), "Inside the bar it comes up")
        manager.commitAnyFloatingPiece()

        let (plain, plainTarget, _) = gradedManager(.blur(Effect.Blur(radius: 3)))
        XCTAssertFalse(plain.beginEffectBoxMove(for: plainTarget), "A blur has no box")
        XCTAssertNil(plain.floatingPiece)
    }

    /// **Distort is refused on the box, in the artist's terms** — §2 ruling 15, and
    /// `distortUnavailableReason`'s new arm: five scalars cannot hold a keystone.
    func testDistortIsRefusedOnTheBoxAndTheReasonNamesIt() {
        let (manager, target, _) = gradedManager(dup { $0.offsetX = 5 })
        XCTAssertTrue(manager.beginEffectBoxMove(for: target))
        XCTAssertNil(manager.distortUnavailableReason, "Nothing to say in Uniform")
        manager.setTransformMode(.distort)
        XCTAssertNotNil(manager.distortUnavailableReason, "Distort on the effect box is refused")
        XCTAssertTrue(manager.distortUnavailableReason?.contains("Duplicate Offset") == true,
                      "…and the sentence names what is in the way: \(manager.distortUnavailableReason ?? "nil")")
        XCTAssertFalse(FloatingPieceKind.effectBox.acceptsDistort)
        XCTAssertTrue(FloatingPieceKind.move.acceptsDistort && FloatingPieceKind.containerPose.acceptsDistort)
        manager.setTransformMode(.uniform)
        manager.commitAnyFloatingPiece()
    }

    /// **On a keyed channel the box writes a key, not the base** — the settings bar's routing,
    /// reached through the second writer. Offset X carries a curve 0 → 40 over ten frames; at frame
    /// 5 the box comes up at 20, the artist drags it to 30, and Done writes a key at frame 5 while
    /// the stored base stays 0. One undo removes the key.
    func testOnAKeyedChannelTheBoxWritesAKeyAtThePlayhead() {
        let (manager, target, index) = gradedManager(dup { $0.color = red })
        var curve = AnimationCurve()
        curve.setKey(AnimationCurve.Key(frame: 0, value: 0, interpolation: .linear))
        curve.setKey(AnimationCurve.Key(frame: 10, value: 40, interpolation: .linear))
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: index, parameterID: "duplicateOffset.offsetX", to: curve))
        manager.currentFrame = 5
        let steps = manager.history.undoStack.count

        XCTAssertTrue(manager.beginEffectBoxMove(for: target))
        XCTAssertEqual(Double(manager.floatingPiece?.transform.position.x ?? -1), 32 + 20, accuracy: 1e-9,
                       "The box comes up at the *resolved* copy, halfway along the curve")
        var dragged = manager.floatingPiece!.transform
        dragged.position.x += 10
        manager.updateFloatingPose(transform: dragged, distortQuad: nil)
        guard case .duplicateOffset(let live)? = manager.resolvedEffect(of: target, atFrame: 5) else { return XCTFail() }
        XCTAssertEqual(live.offsetX, 30, accuracy: 1e-9, "The preview keys the playhead, so the render follows")
        XCTAssertEqual(stored(manager, index)?.offsetX, 0, "…without touching the base a curve overrides")

        manager.commitAnyFloatingPiece()
        XCTAssertEqual(manager.layers[index].effectTracks["duplicateOffset.offsetX"]?.key(atFrame: 5)?.value, 30,
                       "Done wrote a key at the playhead")
        XCTAssertEqual(stored(manager, index)?.offsetX, 0, "The base is untouched")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1)
        XCTAssertEqual(manager.history.undoStack.last?.label, .effectKeyframes, "The step says it wrote keys")

        manager.undo()
        XCTAssertNil(manager.layers[index].effectTracks["duplicateOffset.offsetX"]?.key(atFrame: 5),
                     "One undo takes the key back")
    }

    /// **The rim is what the artist sees on the composited canvas, in both backends** — the effect
    /// through `Compositor.composite` on a real document rather than through the kernel alone: a
    /// black square under a white-paper document, a Duplicate Offset slid right by 8, and the pixel
    /// 4 in from the square's left edge is the effect's red (rim) while the square's middle is still
    /// black (intersection). And with Intersection picked, the reverse.
    func testTheCompositedCanvasShowsTheRimWhereTheCopyMovedAway() {
        for backend in [CompositorBackend.coreGraphics, .metal] {
            if backend == .metal, CompositorMetalEngine.shared == nil { continue }
            Compositor.backend = backend
            defer { Compositor.backend = Compositor.defaultBackend }
            let (manager, _, index) = gradedManager(dup { $0.offsetX = 8; $0.color = red })
            func composite() -> [UInt8]? {
                guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true),
                      let image = Compositor.composite(request) else { return nil }
                return CanvasFixture.rgbaBytes(image)
            }
            guard let rim = composite() else { return XCTFail("\(backend) declined") }
            let leftEdge = pixel(rim, 18, 32), middle = pixel(rim, 32, 32), paper = pixel(rim, 4, 4)
            XCTAssertGreaterThan(leftEdge[0], 200, "\(backend): the rim, 2 px in from the square's left edge, is red")
            XCTAssertLessThan(leftEdge[1], 60)
            XCTAssertLessThan(middle[0] + middle[1] + middle[2], 60, "\(backend): the middle is still the black ink")
            XCTAssertGreaterThan(paper[0] + paper[1] + paper[2], 700, "\(backend): the paper is untouched — nothing outside")

            manager.layers[index].effect = dup { $0.offsetX = 8; $0.region = .intersection; $0.color = red }
            guard let intersection = composite() else { return XCTFail("\(backend) declined") }
            XCTAssertLessThan(pixel(intersection, 18, 32)[0], 60, "\(backend): under Intersection the left edge is ink")
            XCTAssertGreaterThan(pixel(intersection, 32, 32)[0], 200, "\(backend): …and the middle is red")
        }
    }
}
