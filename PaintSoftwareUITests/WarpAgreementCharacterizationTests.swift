import XCTest
import UIKit

/// The two projective warps, measured **against each other** — ADD_TEXT.md §1: *"The Swift and MSL
/// warps must be tested against each other, not each against itself. A green warp test proves its two
/// operands are equal, not that they are the two rasterizers you think."*
///
/// So, stated before any number appears, exactly what each test in this file compares:
///
/// 1. **`testTheTwoBackendsAgreeAcrossAFixedSetOfQuads` compares `warpHomography` in
///    `Composite.metal` against `ImageWarp.warp` in Swift.** Both are this app's code and neither has
///    a third-party primitive behind it — there is no CoreGraphics call that resamples through a
///    homography, which is precisely why §2 had to weigh Core Image and then reject it. What this
///    catches is a transcription slip between the two languages, a `WarpParams` layout that differs
///    between the struct and the shader, a sampler that clamps on one side and goes transparent on
///    the other, and a `w ≤ 0` discard that only one of them does. It is **not** evidence that the
///    homography is right; `HomographyLogicTests` is where that is claimed.
///
/// 2. **`testTheCoreAnimationPreviewAndTheKernelBakeAreMeasuredNotAssumed` is a characterization,
///    not a contract.** §4 records the divergence between the live preview and the bake as a *known
///    open risk* and says plainly: "Do not let 'gated on it being visible' become 'never looked.'"
///    So this looks, prints the figure, and asserts only a tripwire far above it. Fixing the
///    divergence is explicitly not stage 5's, and a tight assertion here would turn an OS-version
///    detail into a red build.
///
///    **MEASURED (simulator, iOS 26.5, `CALayer.render(in:)`, rendered text at 2× into a 192×128
///    box).** Mean absolute channel difference over the whole destination:
///
///    | quad | mean | worst pixel |
///    |---|---|---|
///    | upright / translated | 0.43/255 | 104/255 |
///    | rotated (still a parallelogram) | 0.41/255 | 140/255 |
///    | trapezoid | **7.63/255** | 255/255 |
///    | strong perspective | 6.41/255 | 255/255 |
///    | general (no two edges parallel) | 6.93/255 | 255/255 |
///
///    §4's prediction holds exactly and quantitatively: the divergence is ~15× larger on a
///    foreshortened quad than on an affine one, "worst on exactly the strongly foreshortened quad the
///    feature exists for". The single-pixel 255s are a glyph edge landing on opposite sides of a
///    texel boundary in the two rasterizers; the mean is the number that says what it looks like.
///
///    **Read the figure with its caveat.** `CALayer.render(in:)` is an in-process software path; the
///    artist's preview is composited by the render server on the GPU, whose filtering is the
///    unspecified, OS-version-dependent thing §4 is actually worried about. So this is a floor and a
///    change detector, not the on-device number — that judgement is eyes-on, and it is what stage 5's
///    Release run on the iPad 9 is for.
///
/// The fixtures are byte buffers in the app's layout throughout, for `EffectParityLogicTests`'
/// stated reason: both `ImageWarp.warp` and `MetalWarpEngine.warp` take and return exactly that, so a
/// measured difference is one warp against the other with no `UIGraphicsImageRenderer`, no colour
/// space and no second byte layout in between.
final class WarpAgreementCharacterizationTests: XCTestCase {

    // MARK: - Tolerance, and where it comes from

    /// **Two steps of the 8-bit channel grid, and the two are accounted for separately.**
    ///
    /// One is unavoidable quantisation: both backends finish by rounding a continuous value onto
    /// `0...255`, and they round it with different machinery — Swift's `.rounded()` (half away from
    /// zero) against the GPU's unorm write (half to even). A value that lands within a hair of `x.5`
    /// therefore differs by exactly one step, on any pixel, forever.
    ///
    /// The second is arithmetic width. The kernel works in `float`; the reference reads the same
    /// `Float` parameter block but does the divide and the two lerps in `Double`. Near a strongly
    /// foreshortened quad's far edge the perspective divide's relative error is at its largest, and a
    /// fraction-of-a-texel difference in where the bilinear lands is a second step wherever the
    /// source has a hard edge — which a glyph bitmap is made of.
    ///
    /// **Measured, on the simulator, over the fixture set below: the largest single-channel
    /// disagreement is reported by the test itself and has been 1 in every run so far.** The
    /// tolerance is set at 2 rather than at the measured 1 because the second term above is a real
    /// mechanism whose size depends on the quad, and a tolerance pinned to the fixtures would be a
    /// claim about the fixtures. A regression that mattered — a transposed matrix, a clamped sampler,
    /// a missing discard — moves this by tens or hundreds, not by one.
    private static let channelTolerance = 2

    /// And a second, stricter claim beside it: agreement is not just bounded per pixel, it is *rare*
    /// to differ at all. A backend that had drifted a fraction of a texel everywhere would satisfy
    /// the per-channel bound and fail this.
    private static let maximumDifferingFraction = 0.02

    // MARK: - Fixtures

    private static let sourceWidth = 96
    private static let sourceHeight = 64

    /// **Hard edges, not a smooth ramp**, and that is the point of the fixture rather than a
    /// stylistic choice: a resampler's disagreements live where the gradient is, and a glyph bitmap —
    /// which is what this warp actually carries — is almost entirely edges. A gentle gradient would
    /// let a half-texel sampling error produce a half-step colour error and pass.
    ///
    /// Built premultiplied by hand rather than drawn, so the bytes are stated rather than inherited
    /// from whatever `UIGraphicsImageRenderer` felt like producing. Includes a fully transparent band
    /// and a fully opaque one, which are the two corners the bilinear has to survive, and puts ink
    /// hard against all four borders so a clamp-to-edge sampler would smear visibly.
    private func sourceBytes() -> [UInt8] {
        let w = Self.sourceWidth, h = Self.sourceHeight
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let checker = ((x / 7) + (y / 5)) % 2 == 0
                let alpha = checker ? 255 : (x % 11 == 0 ? 0 : 128)
                let colour = [(x * 5) % 256, (y * 9) % 256, ((x ^ y) * 3) % 256]
                let offset = (x + y * w) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(value) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    /// The box the source bitmap represents, in canvas points. Deliberately not equal to the source's
    /// pixel dimensions, so a warp that confused texels with points cannot pass.
    private let boxSize = CGSize(width: 192, height: 128)

    private var sourceScale: CGFloat { CGFloat(Self.sourceWidth) / boxSize.width }

    /// The fixed set of quads. Each one is a different thing that can be wrong.
    private var quads: [(name: String, quad: Quad)] {
        [
            // Identity-ish: the box where it already is. A warp that is subtly translated by half a
            // texel fails here and nowhere else.
            ("upright", Quad.rect(CGRect(origin: .zero, size: boxSize))),
            // Offset, so the destination origin is genuinely folded into the matrix.
            ("translated", Quad.rect(CGRect(x: 37, y: 21, width: boxSize.width, height: boxSize.height))),
            // Turned: a parallelogram, so the map is affine and the perspective term is exactly zero.
            ("rotated", Quad(CGPoint(x: 60, y: 10), CGPoint(x: 226, y: 106),
                             CGPoint(x: 162, y: 217), CGPoint(x: -4, y: 121))),
            // A wall going away from you — the case the feature exists for.
            ("trapezoid", Quad(CGPoint(x: 0, y: 0), CGPoint(x: 192, y: 34),
                               CGPoint(x: 192, y: 94), CGPoint(x: 0, y: 128))),
            // And a strong one, where the far edge is a fifth of the near edge and the divide is
            // doing most of the work.
            ("strong perspective", Quad(CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 96),
                                        CGPoint(x: 300, y: 108), CGPoint(x: 0, y: 204))),
            // Skewed both ways at once, so no edge is parallel to any other.
            ("general", Quad(CGPoint(x: 20, y: 40), CGPoint(x: 250, y: 5),
                             CGPoint(x: 210, y: 160), CGPoint(x: 8, y: 190)))
        ]
    }

    private func params(for quad: Quad, destination: CGRect) throws -> WarpParams {
        let homography = try XCTUnwrap(Homography(boxSize: boxSize, to: quad))
        let matrix = try XCTUnwrap(ImageWarp.inverseTexelMap(homography: homography, boxSize: boxSize,
                                                             sourceScale: sourceScale,
                                                             destinationOrigin: destination.origin,
                                                             destinationScale: 1))
        return WarpParams(matrix)
    }

    // MARK: - The composition both backends share, and therefore cannot check

    /// **`inverseTexelMap` against the geometry, not against the other backend** — the blind spot the
    /// agreement test below has by construction.
    ///
    /// Every other test in this file hands both warps *the same* `WarpParams`, which is exactly right
    /// for measuring one rasterizer against another and is why the header spells it out. But it means
    /// the one genuinely new composition in the bake path is shared: a `sourceScale` 10% out, or a
    /// destination origin folded in with the wrong sign, produces a matrix on which the kernel and the
    /// scalar reference **agree perfectly and are both wrong** — the text lands 20 pt from where the
    /// artist put it, or resampled from the wrong part of the glyph bitmap, and every assertion in the
    /// file stays green. §1's own warning, one level up: a green test proves its two operands are
    /// equal, not that they are the two things you meant.
    ///
    /// So this states the composition independently, as four maps read right to left, and checks the
    /// matrix against it:
    ///
    /// 1. A destination texel `p` is the canvas point `origin + p / destinationScale`.
    /// 2. That canvas point came from the box point `H⁻¹(·)`.
    /// 3. Which is the source texel `boxPoint × sourceScale`.
    ///
    /// The `Homography` is checked rather than the `WarpParams` built from it, so a disagreement is
    /// the composition and never the `Float` narrowing. Both scales are exercised away from 1 —
    /// `destinationScale` was written from the start and, until the memory cap landed, was only ever
    /// passed 1, so it had never been executed at any other value.
    func testTheInverseTexelMapCarriesDestinationTexelsOntoTheSourceTexelsGeometryNames() throws {
        // A grid over the box, plus its corners: the corners pin the ends of the map and the interior
        // is where a dropped perspective divide shows.
        var samples = Quad.rect(CGRect(origin: .zero, size: boxSize)).points
        for x in stride(from: CGFloat(9), through: boxSize.width, by: 41) {
            for y in stride(from: CGFloat(7), through: boxSize.height, by: 29) {
                samples.append(CGPoint(x: x, y: y))
            }
        }

        for entry in quads {
            let homography = try XCTUnwrap(Homography(boxSize: boxSize, to: entry.quad))
            let destination = entry.quad.boundingBox.integral
            for destinationScale in [CGFloat(1), 0.5, 2.5] {
                let matrix = try XCTUnwrap(
                    ImageWarp.inverseTexelMap(homography: homography, boxSize: boxSize,
                                              sourceScale: sourceScale,
                                              destinationOrigin: destination.origin,
                                              destinationScale: destinationScale),
                    "\(entry.name) at \(destinationScale)×")
                for boxPoint in samples {
                    let canvas = try XCTUnwrap(homography.map(boxPoint))
                    let destinationTexel = CGPoint(x: (canvas.x - destination.minX) * destinationScale,
                                                   y: (canvas.y - destination.minY) * destinationScale)
                    let want = CGPoint(x: boxPoint.x * sourceScale, y: boxPoint.y * sourceScale)
                    let got = try XCTUnwrap(matrix.map(destinationTexel))
                    XCTAssertEqual(got.x, want.x, accuracy: 1e-6 * max(1, abs(want.x)),
                                   "\(entry.name) at \(destinationScale)×, box \(boxPoint): source texel u")
                    XCTAssertEqual(got.y, want.y, accuracy: 1e-6 * max(1, abs(want.y)),
                                   "\(entry.name) at \(destinationScale)×, box \(boxPoint): source texel v")
                }
                // The normalisation: the artwork must be on the positive-weight side, or the kernel's
                // `w ≤ 0` discard throws away the picture instead of the far side of the horizon.
                let centre = try XCTUnwrap(homography.map(CGPoint(x: boxSize.width / 2,
                                                                  y: boxSize.height / 2)))
                XCTAssertGreaterThan(
                    matrix.weight(at: CGPoint(x: (centre.x - destination.minX) * destinationScale,
                                              y: (centre.y - destination.minY) * destinationScale)), 0,
                    "\(entry.name) at \(destinationScale)×: the box's own centre is past the vanishing line.")
            }
        }
    }

    /// And the size of the two slips the shared-parameters blind spot would hide, measured — so a
    /// tolerance that quietly stopped separating them fails here rather than passing.
    ///
    /// Both are matrices the agreement test would call a success: both backends read them identically.
    /// What they are is *the wrong picture*, and the assertion is that "wrong" is tens of texels, not
    /// a rounding.
    func testAMisScaledSourceOrAFlippedDestinationOriginMoveTheSampleFarEnoughToSee() throws {
        let entry = try XCTUnwrap(quads.first { $0.name == "trapezoid" })
        let homography = try XCTUnwrap(Homography(boxSize: boxSize, to: entry.quad))
        let destination = CGRect(x: 137, y: 61, width: 300, height: 200)
        let probe = CGPoint(x: 120, y: 80)

        func sample(sourceScale: CGFloat, origin: CGPoint) throws -> CGPoint {
            let matrix = try XCTUnwrap(ImageWarp.inverseTexelMap(homography: homography, boxSize: boxSize,
                                                                 sourceScale: sourceScale,
                                                                 destinationOrigin: origin,
                                                                 destinationScale: 1))
            return try XCTUnwrap(matrix.map(probe))
        }

        let correct = try sample(sourceScale: sourceScale, origin: destination.origin)
        let mis = try sample(sourceScale: sourceScale * 1.1, origin: destination.origin)
        XCTAssertGreaterThan(hypot(mis.x - correct.x, mis.y - correct.y), 2,
                             "A sourceScale 10% out has to move the sampled texel visibly.")

        let flipped = try sample(sourceScale: sourceScale,
                                 origin: CGPoint(x: -destination.minX, y: -destination.minY))
        XCTAssertGreaterThan(hypot(flipped.x - correct.x, flipped.y - correct.y), 20,
                             "A sign-flipped destination origin has to move the sampled texel visibly.")
    }

    // MARK: - What the destination is allowed to cost

    /// **The memory bound, as arithmetic.** ADD_TEXT.md §2 predicted the failure — *"'the destination
    /// is the quad's bbox, never the canvas' is not a bound"* — and a corner dragged off-canvas makes
    /// it worse than the prediction: a quad corner at (50 000, 50 000) is a bounding box of 2.5
    /// billion points, and `warpedImage` holds three `w × h × 4` buffers of it at once against §4 rule
    /// 6's 192 MiB.
    ///
    /// Two claims, because there are two mechanisms and the first one does almost all the work:
    /// `warpedGlyphs` intersects the destination with what the caller can actually show, which is
    /// **lossless** — a texel outside the destination context can never be seen and can never be
    /// saved. `destinationScale` is what remains after that, for a destination that is on-canvas and
    /// still enormous, and it is a soft edge rather than a refusal: past the cap the warp is
    /// rasterised smaller and drawn up into the full rectangle.
    func testTheWarpDestinationIsCappedRatherThanTrustedToBeSmall() throws {
        // Below the cap nothing happens at all, so the bound cannot change what stage 5 shipped.
        XCTAssertEqual(ImageWarp.destinationScale(for: CGRect(x: 0, y: 0, width: 4096, height: 4096),
                                                  maximumTexels: 4096), 1)
        XCTAssertEqual(ImageWarp.destinationScale(for: CGRect(x: -900, y: -900, width: 10, height: 4000),
                                                  maximumTexels: 4096), 1)
        // Above it, the longest side lands exactly on the cap.
        let huge = CGRect(x: 0, y: 0, width: 50_000, height: 1_200)
        let scale = ImageWarp.destinationScale(for: huge, maximumTexels: 4096)
        XCTAssertEqual(huge.width * scale, 4096, accuracy: 1e-9)
        XCTAssertLessThan(huge.height * scale, 4096)

        // And `warpedImage` actually honours it — asked for a destination 40 times the cap it returns
        // an image at the cap, not one that would have been 1.9 GiB of transient. A small cap so the
        // test costs kilobytes; the arithmetic is the same at 4096.
        let quad = try XCTUnwrap(quads.first { $0.name == "trapezoid" }).quad
        let homography = try XCTUnwrap(Homography(boxSize: boxSize, to: quad))
        let source = try XCTUnwrap(CoreGraphicsCompositor.makeImage(fromPremultiplied: sourceBytes(),
                                                                     width: Self.sourceWidth,
                                                                     height: Self.sourceHeight))
        let capped = try XCTUnwrap(ImageWarp.warpedImage(source: source, sourceScale: sourceScale,
                                                         boxSize: boxSize, homography: homography,
                                                         destination: CGRect(x: 0, y: 0,
                                                                             width: 2_560, height: 1_280),
                                                         maximumDestinationTexels: 64))
        XCTAssertEqual(capped.width, 64, "The longest side has to land on the cap.")
        XCTAssertEqual(capped.height, 32, "And the other side keeps the destination's aspect ratio.")
    }

    /// The clip, on the path that actually allocates: a text box with one corner dragged far
    /// off-canvas produces a destination bounded by the canvas, not by the quad.
    ///
    /// The assertion is the ratio rather than a byte count, because the byte count is the ratio times
    /// four and the ratio is the claim: `TextLayout.warpedGlyphs` used to hand `ImageWarp` the frame's
    /// whole bounding box.
    func testAFrameDraggedOffCanvasWarpsIntoTheCanvasAndNotIntoItsOwnBoundingBox() throws {
        let canvas = CGRect(x: 0, y: 0, width: 512, height: 512)
        var frame = TextFrame(origin: CGPoint(x: 40, y: 40), size: CGSize(width: 200, height: 80),
                              autoSize: false)
        frame.corners[TextFrame.Corner.bottomRight.rawValue] = CGPoint(x: 50_000, y: 50_000)
        frame.mode = .projective
        XCTAssertNotNil(frame.homography, "The fixture has to be a frame the warp path would accept.")
        XCTAssertGreaterThan(frame.boundingBox.width * frame.boundingBox.height,
                             canvas.width * canvas.height * 1_000,
                             "The unclipped destination has to be enormous, or nothing is being bounded.")

        let warped = try XCTUnwrap(TextLayout.warpedGlyphs(recipe: TextRecipe(string: "Wall", font: .system,
                                                                              typography: Typography(pointSize: 32)),
                                                            frame: frame, clip: canvas))
        XCTAssertTrue(canvas.contains(warped.destination),
                      "The destination must lie inside what the caller can show: got \(warped.destination).")
        XCTAssertLessThanOrEqual(warped.image.size.width * warped.image.size.height,
                                 canvas.width * canvas.height,
                                 "And the bitmap with it.")

        // A box dragged entirely off-canvas has no destination at all, and the caller falls through.
        var gone = frame
        gone.corners = frame.corners.map { CGPoint(x: $0.x + 20_000, y: $0.y + 20_000) }
        XCTAssertNil(TextLayout.warpedGlyphs(recipe: TextRecipe(string: "Wall", font: .system,
                                                                typography: Typography(pointSize: 32)),
                                             frame: gone, clip: canvas),
                     "An empty intersection is nothing to draw, not a zero-sized allocation.")
    }

    // MARK: - The agreement

    func testTheTwoBackendsAgreeAcrossAFixedSetOfQuads() throws {
        let engine = try XCTUnwrap(MetalWarpEngine.shared,
                                   "No Metal warp pipeline — the kernel is not in the test bundle's metallib.")
        let source = sourceBytes()
        var worstChannel = 0
        var worstQuad = ""

        for entry in quads {
            let destination = entry.quad.boundingBox.integral
            let width = Int(destination.width), height = Int(destination.height)
            let params = try params(for: entry.quad, destination: destination)

            let reference = try XCTUnwrap(ImageWarp.warp(source: source,
                                                         sourceWidth: Self.sourceWidth,
                                                         sourceHeight: Self.sourceHeight,
                                                         destinationWidth: width,
                                                         destinationHeight: height,
                                                         params: params),
                                          "\(entry.name): the scalar reference declined.")
            let kernel = try XCTUnwrap(engine.warp(source, sourceWidth: Self.sourceWidth,
                                                   sourceHeight: Self.sourceHeight,
                                                   destinationWidth: width, destinationHeight: height,
                                                   params: params),
                                       "\(entry.name): the kernel declined.")
            XCTAssertEqual(reference.count, kernel.count)

            // The fixture has to actually land in the destination, or "they agree" would be two
            // buffers of zeroes agreeing.
            let covered = stride(from: 3, to: reference.count, by: 4).filter { reference[$0] > 0 }.count
            XCTAssertGreaterThan(Double(covered) / Double(width * height), 0.2,
                                 "\(entry.name): the warp put almost nothing in the destination.")

            var differing = 0
            var quadWorst = 0
            for index in 0..<min(reference.count, kernel.count) {
                let delta = abs(Int(reference[index]) - Int(kernel[index]))
                if delta > 0 { differing += 1 }
                quadWorst = max(quadWorst, delta)
            }
            if quadWorst > worstChannel { worstChannel = quadWorst; worstQuad = entry.name }
            XCTAssertLessThanOrEqual(quadWorst, Self.channelTolerance,
                                     "\(entry.name): the two warps disagree by \(quadWorst) channel steps.")
            XCTAssertLessThanOrEqual(Double(differing) / Double(reference.count),
                                     Self.maximumDifferingFraction,
                                     "\(entry.name): \(differing) of \(reference.count) channels differ at all.")
        }
        print("MEASURED Swift-vs-MSL warp: worst single-channel disagreement \(worstChannel)/255, on '\(worstQuad)'.")
    }

    /// The `w ≤ 0` discard, isolated. A destination pixel on the far side of the vanishing line has
    /// no source at all, and **both** backends must write transparent there rather than sampling
    /// something plausible.
    ///
    /// Reached by handing the warp a matrix whose weight goes negative inside the destination, which
    /// `isValidQuad` would refuse at the drag — so this is the guard behind the guard, and it is worth
    /// having: `Homography` is general geometry that a later Move Distort will compose with other
    /// transforms, and composition can produce a matrix no quad was ever checked against.
    func testBothBackendsDiscardWhereTheWeightIsNotPositive() throws {
        let engine = try XCTUnwrap(MetalWarpEngine.shared)
        let source = sourceBytes()
        let width = 128, height = 96
        // Weight crosses zero down the middle of the destination.
        var params = WarpParams(Homography(a: CGFloat(Self.sourceWidth) / CGFloat(width), b: 0, c: 0,
                                           d: 0, e: CGFloat(Self.sourceHeight) / CGFloat(height), f: 0,
                                           g: -1 / CGFloat(width / 2), h: 0, i: 1))
        params.m8 = 1

        let reference = try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: Self.sourceWidth,
                                                     sourceHeight: Self.sourceHeight,
                                                     destinationWidth: width, destinationHeight: height,
                                                     params: params))
        let kernel = try XCTUnwrap(engine.warp(source, sourceWidth: Self.sourceWidth,
                                               sourceHeight: Self.sourceHeight,
                                               destinationWidth: width, destinationHeight: height,
                                               params: params))
        // The right half is past the vanishing line.
        var discarded = 0
        for y in 0..<height {
            for x in (width / 2 + 2)..<width {
                let offset = (y * width + x) * 4
                XCTAssertEqual(reference[offset + 3], 0, "reference kept a pixel past the vanishing line")
                XCTAssertEqual(kernel[offset + 3], 0, "kernel kept a pixel past the vanishing line")
                discarded += 1
            }
        }
        XCTAssertGreaterThan(discarded, 0)
        // And the left half is not empty, or the two agree about nothing.
        let kept = stride(from: 3, to: reference.count, by: 4).filter { reference[$0] > 0 }.count
        XCTAssertGreaterThan(kept, 0, "Everything was discarded — the fixture proves nothing.")
    }

    /// **A weight that is positive but vanishingly small must draw nothing, not take the process
    /// down** — the one place the scalar loop can crash rather than decline.
    ///
    /// `w > 0` lets through a destination pixel a hair *inside* the vanishing line, and there `u` and
    /// `v` come out at 1e17 and beyond. `Int(_:)` on a `Double` that will not fit **traps** in Swift;
    /// it does not saturate and it does not wrap. The GPU has no such cliff — `int(base.x)` in MSL is
    /// undefined-but-quiet and every branch it feeds is a bounds test that answers "outside" — so this
    /// is a hazard the scalar reference has and the kernel does not, which is exactly the kind the
    /// agreement tests above cannot see.
    ///
    /// The fixture states the condition directly rather than hunting for a quad that produces it: a
    /// denormal weight, positive everywhere, so every pixel takes the branch at once. Refusing is not
    /// an approximation of sampling — a `u` outside `(-1, sourceWidth)` puts *both* bilinear taps out
    /// of bounds, and both come back transparent, so the blend would have written zero anyway.
    ///
    /// Only the reference is asserted. The kernel's behaviour here is genuinely undefined by the MSL
    /// spec, and a test that pinned it would be pinning a compiler's current mood.
    func testAWeightAHairAboveZeroDrawsNothingRatherThanTrapping() throws {
        let width = 24, height = 16
        var params = WarpParams(Homography(a: 0.5, b: 0, c: 0, d: 0, e: 0.5, f: 0, g: 0, h: 0, i: 1))
        params.m8 = 1e-40 // positive, denormal: `u` lands around 1e39, far past `Int.max`
        XCTAssertGreaterThan(params.m8, 0, "A non-positive weight is the other test's case.")

        let out = try XCTUnwrap(ImageWarp.warp(source: sourceBytes(), sourceWidth: Self.sourceWidth,
                                                sourceHeight: Self.sourceHeight,
                                                destinationWidth: width, destinationHeight: height,
                                                params: params))
        XCTAssertEqual(out.count, width * height * 4)
        XCTAssertTrue(out.allSatisfy { $0 == 0 },
                      "A source texel index past `Int.max` has to be declined, not converted.")
    }

    /// The source's outside is **transparent, not clamped**. A sized text box clips its glyphs, so
    /// its edge texels can be opaque ink; clamping would smear that ink outward as an infinite skirt.
    ///
    /// Asked of a destination deliberately larger than the quad, so there are pixels that map outside
    /// the source rectangle to look at.
    func testOutsideTheSourceIsTransparentInBothBackends() throws {
        let engine = try XCTUnwrap(MetalWarpEngine.shared)
        let source = sourceBytes()
        let quad = Quad.rect(CGRect(x: 40, y: 30, width: boxSize.width, height: boxSize.height))
        // Two boxes' worth of destination around a one-box quad.
        let destination = quad.boundingBox.insetBy(dx: -40, dy: -30).integral
        let width = Int(destination.width), height = Int(destination.height)
        let params = try params(for: quad, destination: destination)

        let reference = try XCTUnwrap(ImageWarp.warp(source: source, sourceWidth: Self.sourceWidth,
                                                     sourceHeight: Self.sourceHeight,
                                                     destinationWidth: width, destinationHeight: height,
                                                     params: params))
        let kernel = try XCTUnwrap(engine.warp(source, sourceWidth: Self.sourceWidth,
                                               sourceHeight: Self.sourceHeight,
                                               destinationWidth: width, destinationHeight: height,
                                               params: params))
        for y in 0..<height {
            for x in 0..<width where x < 20 || y < 15 {
                let offset = (y * width + x) * 4
                XCTAssertEqual(reference[offset + 3], 0, "reference smeared the source's edge outward")
                XCTAssertEqual(kernel[offset + 3], 0, "kernel smeared the source's edge outward")
            }
        }
    }

    // MARK: - The known open risk, measured

    /// **The Core-Animation preview against the kernel bake, measured and reported rather than
    /// asserted into agreement.**
    ///
    /// ADD_TEXT.md §4 records this as an open risk and stage 5's entry lists WYSIWYG convergence as
    /// explicitly not in scope: live is Core Animation warping a CA-managed bitmap, bake is our kernel
    /// at canvas scale, and while the projective *map* is shared, the sampling, the gamma handling and
    /// the premultiplication are not — CA's filtering is unspecified and OS-version-dependent. The
    /// document's instruction is the one this test exists to obey: *"Do not let 'gated on it being
    /// visible' become 'never looked.'"*
    ///
    /// **What this measures is `CALayer.render(in:)`, which is not the render server**, and the
    /// difference matters when reading the number: `render(in:)` is a software path in-process, while
    /// the artist's preview is composited by the render server on the GPU. So this is a floor on the
    /// divergence and a change detector, not the on-device figure. The on-device judgement is
    /// eyes-on, which is what stage 5's Release run on the iPad 9 is for.
    ///
    /// The assertion is a tripwire two orders above the measurement: it fires if the preview stops
    /// being recognisably the same picture (a lost transform, a transposition, an empty layer), and
    /// stays quiet for the resampling differences that are the actual subject.
    func testTheCoreAnimationPreviewAndTheKernelBakeAreMeasuredNotAssumed() throws {
        // **Real glyphs, not the checkerboard the agreement test uses.** The checker is deliberately
        // adversarial — a feature every seven pixels, so a resampler's disagreements are maximal —
        // and that is right for measuring two implementations of one rule against each other. It is
        // the wrong fixture for this measurement, and measurably so: run against the checker, the
        // projective quads come out at mean 54-72/255, and almost all of that is two samplers aliasing
        // a high-frequency pattern differently under minification rather than anything an artist would
        // ever put in a text box. `TextLayout.renderBox` is what the feature actually warps.
        let recipe = TextRecipe(string: "Perspective", font: .system,
                                typography: Typography(pointSize: 44))
        let sourceImage = try XCTUnwrap(TextLayout.renderBox(recipe: recipe, boxSize: boxSize,
                                                             clip: true, scale: 2)?.cgImage)
        let textScale = CGFloat(sourceImage.width) / boxSize.width
        var lines: [String] = []
        var worstMean = 0.0
        var worstName = ""

        for entry in quads {
            let destination = entry.quad.boundingBox.integral
            let width = Int(destination.width), height = Int(destination.height)
            let homography = try XCTUnwrap(Homography(boxSize: boxSize, to: entry.quad))

            let baked = try XCTUnwrap(ImageWarp.warpedImage(source: sourceImage, sourceScale: textScale,
                                                            boxSize: boxSize, homography: homography,
                                                            destination: destination,
                                                            maximumDestinationTexels: 4096))
            let bakedBytes = try XCTUnwrap(CoreGraphicsCompositor.premultipliedBytes(baked, width: width,
                                                                                     height: height))
            let previewBytes = try XCTUnwrap(coreAnimationPreview(source: sourceImage,
                                                                  sourceScale: textScale,
                                                                  homography: homography,
                                                                  destination: destination))

            var sum = 0.0
            var worstChannel = 0
            var inked = 0
            for index in 0..<min(bakedBytes.count, previewBytes.count) {
                let delta = abs(Int(bakedBytes[index]) - Int(previewBytes[index]))
                sum += Double(delta)
                worstChannel = max(worstChannel, delta)
                if index % 4 == 3, bakedBytes[index] > 0 { inked += 1 }
            }
            let mean = sum / Double(bakedBytes.count)
            XCTAssertGreaterThan(inked, 0, "\(entry.name): nothing was baked, so nothing was compared.")
            let label = entry.name.padding(toLength: 20, withPad: " ", startingAt: 0)
            lines.append(String(format: "  %@ mean %6.2f/255   worst %3d/255   (%d inked px)",
                                label, mean, worstChannel, inked))
            if mean > worstMean { worstMean = mean; worstName = entry.name }
        }

        print("MEASURED CA preview vs warpHomography bake — rendered text, CALayer.render(in:), simulator:")
        lines.forEach { print($0) }
        print(String(format: "  worst case: '\(worstName)' at mean %.2f/255", worstMean))

        XCTAssertLessThan(worstMean, 32,
                          "The preview and the bake have stopped being the same picture, which is a "
                          + "different failure from the resampling divergence this test records.")
    }

    /// One Core Animation render of the warped bitmap, into the destination rectangle.
    ///
    /// The layer is set up exactly as `TextOverlayView` sets its glyph layer up — bounds are the box,
    /// `anchorPoint` and `position` are zero so the transform *is* the layer-to-superlayer map,
    /// `allowsEdgeAntialiasing` on — with one extra translation, folded into the matrix, that moves
    /// the destination's origin to zero.
    private func coreAnimationPreview(source: CGImage, sourceScale: CGFloat,
                                      homography: Homography, destination: CGRect) -> [UInt8]? {
        let shifted = Homography.translation(x: -destination.minX, y: -destination.minY) * homography
        let glyph = CALayer()
        glyph.anchorPoint = .zero
        glyph.position = .zero
        glyph.bounds = CGRect(origin: .zero, size: boxSize)
        glyph.contentsScale = sourceScale
        glyph.magnificationFilter = .linear
        glyph.allowsEdgeAntialiasing = true
        glyph.contents = source
        glyph.transform = shifted.catransform3D

        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: destination.size)
        container.addSublayer(glyph)

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: destination.size, format: format).image { context in
            container.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage else { return nil }
        return CoreGraphicsCompositor.premultipliedBytes(cgImage, width: Int(destination.width),
                                                         height: Int(destination.height))
    }
}
