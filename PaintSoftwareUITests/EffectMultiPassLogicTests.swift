import XCTest
import UIKit

/// Blur and bloom — LAYER_COMPOSITING.md §7's two multi-pass Tier 3 items, phase 9's second half.
///
/// **Read `EffectParityLogicTests`' header first: the three-questions warning it opens with applies
/// here unchanged, and one of the three answers differently for these two effects.**
///
/// 1. **`testTheMultiPassEffectsAgreeBetweenTheBackends` compares `applyEffect` in `Composite.metal`
///    against `EffectReference` in Swift.** Both are this app's code, and neither blur nor bloom has a
///    CoreGraphics primitive — `CGContext` has no convolution — so there is no third party anywhere in
///    that number. It catches transcription slips, a layout disagreement between the two `EffectParams`
///    declarations, a wrong kind code, and — new here — a ping-pong that fed a pass the wrong texture.
///
/// 2. **The property tests below are the half that says something is *right*, and for these two effects
///    they can say more than a spot check could.** A blur has no published formula to transcribe, but it
///    has properties that pin it exactly: a normalized kernel over a flat colour must return that
///    colour, and a separable two-pass blur of an impulse must reproduce the outer product of its own
///    weights. The second is the strong one — it is checkable against `Effect.weights` alone, and it
///    fails if the pass list, the ping-pong, or the separability claim is wrong, without knowing
///    anything about how either backend is written.
///
/// 3. **`Effect.reshapesCoverage` is the wrapper claim, and it is asserted in both directions.** The
///    grades must not touch alpha and these two must, because a blur that left the silhouette sharp is
///    not a blur.
///
/// 4. **Section (2c) is the half that answers the third question — is the formula right — and it is
///    the only part of this file that can.** Kinds 1 and 2 above both consume values `Effect` resolved,
///    so neither can see an error made once in Swift and handed to both backends identically. (2c)
///    computes its expectations from `exp(-d²/2σ²)` and from hand-worked bytes, in the test, and runs
///    the shader as well as the reference against them. Read its header before trusting any number in
///    this file as evidence that blur and bloom are *correct* rather than merely consistent.
///
/// Nothing here goes through `Compositor` or `RenderRequest`: this file pins the pass list and the
/// arithmetic, so its fixtures are byte buffers in the app's layout, for the reason the sibling file
/// gives. That scope is deliberate, but it is now a *gap* rather than a fact about the tree — the
/// §4.4 wrappers exist as of this merge, and a multi-pass effect reaching one has never executed.
/// Neither suite covers the join: `EffectLayerLogicTests` drives the wrappers with single-pass grades
/// only, and this file drives multi-pass with no wrapper. A blur and a bloom *as a stack layer*,
/// graded through the compositor in both backends, is the case that closes it.
final class EffectMultiPassLogicTests: XCTestCase {

    private static let side = 64

    // MARK: - Fixtures

    /// Every pixel a different (colour, alpha) combination — `EffectParityLogicTests.spectrumBytes`,
    /// restated here rather than shared, because a fixture two suites can silently change out from
    /// under each other is how a measured table stops meaning what its comment says.
    ///
    /// It matters more for a convolution than for a grade: a blur reads a neighbourhood, so a fixture
    /// with flat regions would let a kernel that dropped half its taps still agree with one that did
    /// not. Every tap here lands on a different value.
    private func spectrumBytes() -> [UInt8] {
        let side = Self.side
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let colour = [x * 4, y * 4, ((x + y) * 2) % 256]
                let alpha = min(255, (x / 8) * 36 + (y / 16) * 3)
                let offset = (x + y * side) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    private func flatBytes(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = r
            bytes[pixel + 1] = g
            bytes[pixel + 2] = b
            bytes[pixel + 3] = a
        }
        return bytes
    }

    /// One opaque white pixel in a transparent field — the fixture the separability test needs, since
    /// the blur of an impulse *is* the kernel.
    private func impulseBytes(at point: (x: Int, y: Int)) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        let offset = (point.x + point.y * Self.side) * 4
        for channel in 0..<4 { bytes[offset + channel] = 255 }
        return bytes
    }

    /// A hard-edged opaque square on transparency: a silhouette, so "did coverage move" is a question
    /// with an unambiguous answer.
    private func squareBytes(inset: Int, value: UInt8 = 220) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for y in inset..<(Self.side - inset) {
            for x in inset..<(Self.side - inset) {
                let offset = (x + y * Self.side) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        return bytes
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let offset = (x + y * Self.side) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8]) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: Self.side, height: Self.side)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil,
                      "No Metal device or no effect shader library in this test bundle")
    }

    // MARK: - The effects under test

    /// **Both blur shapes and both tap paths.** `directionalAtAnAngle` is the only entry whose taps land
    /// off the pixel grid, which is the branch the axis-aligned Gaussian never takes and the one where
    /// the GPU's bilinear filter and the Swift one have to agree four texels at a time.
    private static let sweep: [(String, Effect)] = [
        ("gaussianSmall", .blur(Effect.Blur(radius: 2))),
        ("gaussianLarge", .blur(Effect.Blur(radius: 9))),
        ("directionalOnAxis", .blur(Effect.Blur(radius: 5, angleDegrees: 0, isDirectional: true))),
        ("directionalAtAnAngle", .blur(Effect.Blur(radius: 6, angleDegrees: 27, isDirectional: true))),
        ("bloom", .bloom(Effect.Bloom(threshold: 0.4, radius: 5, intensity: 0.9))),
        ("bloomWide", .bloom(Effect.Bloom(threshold: 0.15, radius: 12, intensity: 1.6))),
    ]

    /// The parameters that mean "do nothing". Both are reachable from a UI at rest: a blur slider at
    /// zero and a glow at zero strength.
    private static let identities: [(String, Effect)] = [
        ("blur", .blur(Effect.Blur(radius: 0))),
        ("directionalBlur", .blur(Effect.Blur(radius: 0, angleDegrees: 45, isDirectional: true))),
        ("bloomAtZeroIntensity", .bloom(Effect.Bloom(threshold: 0.4, radius: 6, intensity: 0))),
        ("bloomAtAThresholdNothingReaches", .bloom(Effect.Bloom(threshold: 1, radius: 6, intensity: 1))),
        // out = in + 0·(in − blur(in)) = in, for any radius, because the difference is multiplied by
        // zero even though both blur passes really ran and quantized twice.
        ("sharpenAtZeroAmount", .sharpen(Effect.Sharpen(radius: 5, amount: 0))),
        // taps == 0 makes blur1D a pass-through, so in − blur(in) = 0 for ANY amount.
        ("sharpenAtZeroRadius", .sharpen(Effect.Sharpen(radius: 0, amount: 2))),
    ]

    // MARK: - (1) The two backends

    /// Matched to the blend modes' and the grades': one channel step is what independent quantization
    /// can always produce, and anything above it is a formula disagreement.
    private static let tolerance = 1

    /// **Every multi-pass effect through both backends, over 4096 (colour, alpha) pairs.**
    ///
    /// This is the case that would catch a ping-pong bug, and it is worth naming what that would look
    /// like: an intermediate written and then read from the wrong slot does not crash and does not
    /// produce noise — it produces a *single-pass* blur, which is a perfectly plausible picture that
    /// happens to be wrong in one axis. Nothing but a second implementation notices.
    ///
    /// Measured maximum channel delta — simulator, this fixture, **`applyEffect` in `Composite.metal`
    /// against `EffectReference` in Swift**, two implementations written by one hand in one sitting:
    /// the table is recorded in the activity below and in the commit, not asserted per effect, because
    /// the tolerance is the claim.
    func testTheMultiPassEffectsAgreeBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()

        var deltas: [(String, Int)] = []
        for (name, effect) in Self.sweep {
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name), which it should have handled"); continue
            }
            deltas.append((name, maxChannelDelta(gpu, cpu(effect, bytes))))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        // An activity rather than a `print`: a test's stdout does not reliably reach the build log from
        // the runner app, and this table is the measurement.
        XCTContext.runActivity(named: "[multipass] Metal-vs-Swift max channel delta: \(table)") { _ in }

        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                     "\(name) differs by \(delta) between the shader and the Swift reference, past the \(Self.tolerance) the blend modes hold to. Table: \(table)")
        }
    }

    /// A blur is the first effect whose two backends disagree about *where* as well as by how much, so
    /// the edge is measured separately: clamp-to-edge is a convention both sides implement themselves
    /// (Metal's `read` has no addressing mode — `texelClamped` is hand-written on both sides), and a
    /// mismatch there would hide inside a whole-buffer maximum dominated by the interior.
    func testTheBackendsAgreeAtTheCanvasEdgeWhereTheKernelIsClamped() throws {
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let effect = Effect.blur(Effect.Blur(radius: 9))
        guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined a radius-9 blur")
        }
        let reference = cpu(effect, bytes)

        var worst = 0
        for y in 0..<Self.side {
            for x in 0..<Self.side where x < 9 || y < 9 || x >= Self.side - 9 || y >= Self.side - 9 {
                let offset = (x + y * Self.side) * 4
                for channel in 0..<4 {
                    worst = max(worst, abs(Int(gpu[offset + channel]) - Int(reference[offset + channel])))
                }
            }
        }
        XCTContext.runActivity(named: "[multipass] edge band max channel delta: \(worst)") { _ in }
        XCTAssertLessThanOrEqual(worst, Self.tolerance,
                                 "The two clamp-to-edge implementations disagree by \(worst) inside the kernel's reach of the border")
    }

    // MARK: - (2) The properties that say the blur is right

    /// **A normalized kernel over a flat colour returns that colour, everywhere including the border.**
    ///
    /// Two claims in one, and the border half is the interesting one: with clamp-to-edge every tap that
    /// falls off the canvas repeats the edge texel, so the weights still sum to 1 there and the border
    /// cannot darken. The alternative convention — sampling transparent black outside — would fail this
    /// test in a band `radius` wide, which is exactly the grey vignette a blur gets when nobody checks.
    ///
    /// Asserted byte for byte rather than within a tolerance. The weights sum to 1 in `Double` before
    /// they are narrowed, so the float sum lands within ~1e-7 of the input and quantizes back onto it.
    func testABlurOfAFlatColourIsThatColourIncludingAtTheBorder() {
        let bytes = flatBytes(90, 160, 40)
        for radius in [1.0, 4.0, 17.0] {
            XCTAssertEqual(maxChannelDelta(cpu(.blur(Effect.Blur(radius: radius)), bytes), bytes), 0,
                           "A radius-\(radius) blur changed a flat colour, so its weights do not sum to 1 or its edge clamp is wrong")
        }
    }

    /// **The separability claim, checked against `Effect.weights` and nothing else.**
    ///
    /// A two-pass separable blur of a single opaque pixel must reproduce the outer product of its own
    /// 1D kernel: the value at `(±i, ±j)` is `w[i] * w[j]`. This is the strongest statement in the file
    /// because it does not know how either backend is written — it fails if the pass list is one entry
    /// long, if the second pass ran on the wrong axis, if the ping-pong fed a pass the wrong texture, or
    /// if the weights reaching the kernel are not the weights `Effect` resolved.
    ///
    /// **The measured deviation is not zero, and the reason is worth recording: the intermediate is
    /// RGBA8.** The first pass's output is quantized to bytes before the second pass reads it, so a
    /// two-pass blur quantizes twice. That is a deliberate memory choice, not an oversight — §5.3 puts a
    /// canvas texture at 16.8 MB at 2048² and 64 MB at 4000², and a float16 ping-pong would double both
    /// for a peak error of one channel step on an impulse, which is the least representative input a
    /// blur will ever see. On a real image the intermediate is not near zero and the error is smaller.
    func testATwoPassBlurOfAnImpulseIsTheOuterProductOfItsOwnWeights() {
        let radius = 3.0
        let effect = Effect.blur(Effect.Blur(radius: radius))
        let weights = effect.weights
        let centre = (x: Self.side / 2, y: Self.side / 2)
        let out = cpu(effect, impulseBytes(at: centre))

        var worst = 0
        for dy in -3...3 {
            for dx in -3...3 {
                let ideal = Double(weights[abs(dx)]) * Double(weights[abs(dy)])
                let expected = Int((min(max(ideal, 0), 1) * 255).rounded())
                let got = pixel(out, centre.x + dx, centre.y + dy)
                for channel in 0..<4 { worst = max(worst, abs(got[channel] - expected)) }
            }
        }
        XCTContext.runActivity(named: "[multipass] impulse vs w[i]*w[j], max channel deviation: \(worst)") { _ in }
        XCTAssertLessThanOrEqual(worst, 2,
                                 "The separable blur of an impulse deviates from its own outer product by \(worst), past what an RGBA8 intermediate can explain")
    }

    /// A single pass is one axis and not both: a directional blur at 0° must leave every column it did
    /// not sample untouched, which a Gaussian of the same radius does not.
    ///
    /// The assertion is about the *pass list*, not the kernel — one entry versus two — and it is the
    /// thing a reader would otherwise have to take on trust from `Effect.passes`.
    func testADirectionalBlurRunsOneAxisAndAGaussianRunsBoth() {
        let bytes = impulseBytes(at: (x: Self.side / 2, y: Self.side / 2))
        let centre = Self.side / 2

        let directional = cpu(.blur(Effect.Blur(radius: 4, angleDegrees: 0, isDirectional: true)), bytes)
        XCTAssertEqual(pixel(directional, centre, centre - 2)[3], 0,
                       "A horizontal-only blur must not have moved anything vertically")
        XCTAssertGreaterThan(pixel(directional, centre - 2, centre)[3], 0,
                             "…and must have moved it horizontally")

        let gaussian = cpu(.blur(Effect.Blur(radius: 4)), bytes)
        XCTAssertGreaterThan(pixel(gaussian, centre, centre - 2)[3], 0,
                             "A Gaussian is two passes, so the impulse must have spread vertically too")
        XCTAssertEqual(Effect.blur(Effect.Blur(radius: 4)).passes.count, 2)
        XCTAssertEqual(Effect.blur(Effect.Blur(radius: 4, isDirectional: true)).passes.count, 1)
    }

    /// The angle is an angle: at 90° the impulse spreads down the column and not along the row, which is
    /// the transpose of the 0° case and catches a sin/cos swap that a parity sweep cannot see (both
    /// backends read the same `offsetX`/`offsetY`, so both would swap together — the blind spot
    /// `Effect.swift`'s header names).
    func testTheDirectionalAngleIsMeasuredFromThePositiveXAxis() {
        let bytes = impulseBytes(at: (x: Self.side / 2, y: Self.side / 2))
        let centre = Self.side / 2
        let out = cpu(.blur(Effect.Blur(radius: 4, angleDegrees: 90, isDirectional: true)), bytes)
        XCTAssertGreaterThan(pixel(out, centre, centre - 2)[3], 0, "90° must spread along y")
        XCTAssertEqual(pixel(out, centre - 2, centre)[3], 0, "…and not along x")
    }

    /// **A blur softens a silhouette, which means it changes alpha** — the property `reshapesCoverage`
    /// declares and the one thing about these two effects that breaks the grades' contract on purpose.
    /// A blur whose output still had two alpha values would be blurring colour inside a razor-sharp
    /// shape, which is the failure this pins.
    func testABlurSpreadsCoverageRatherThanOnlyColour() {
        let bytes = squareBytes(inset: 16)
        let out = cpu(.blur(Effect.Blur(radius: 4)), bytes)
        let alphas = Set(stride(from: 3, to: out.count, by: 4).map { out[$0] })
        XCTAssertGreaterThan(alphas.count, 4,
                             "A blurred silhouette must carry a gradient of coverage, not \(alphas.count) values")
        XCTAssertGreaterThan(pixel(out, 14, Self.side / 2)[3], 0,
                             "Coverage must have moved outside the original square")
    }

    /// A blur is a weighted average, so it cannot invent a value outside the range it read — no ringing,
    /// which is the visible difference between a Gaussian and a sharpening kernel with a negative lobe.
    func testABlurNeverOvershootsTheRangeItRead() {
        let bytes = squareBytes(inset: 16, value: 200)
        let out = cpu(.blur(Effect.Blur(radius: 6)), bytes)
        for value in out { XCTAssertLessThanOrEqual(value, 255) }
        XCTAssertLessThanOrEqual(out.max() ?? 0, 255)
        // The premultiplied invariant, which a convex combination preserves and a bad one would not.
        for pixelStart in stride(from: 0, to: out.count, by: 4) {
            let alpha = out[pixelStart + 3]
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(out[pixelStart + channel], alpha,
                                         "Blur produced rgb above alpha at byte \(pixelStart), which is not a representable premultiplied colour")
            }
        }
    }

    /// The resolved weights are the thing both backends are handed, so they are asserted directly
    /// against the Gaussian they claim to be — computed here from `exp(-i²/2σ²)` independently of
    /// `Effect`'s own loop, which is the only way this says anything the implementation does not.
    func testTheResolvedWeightsAreANormalizedGaussianAtSigmaRadiusOverThree() {
        let radius = 12.0
        let weights = Effect.blur(Effect.Blur(radius: radius)).weights
        XCTAssertEqual(weights.count, 13, "radius 12 is 12 taps a side plus the centre")

        let sigma = radius / 3
        let ideal = (0...12).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = ideal[0] + 2 * ideal.dropFirst().reduce(0, +)
        for i in 0...12 {
            XCTAssertEqual(Double(weights[i]), ideal[i] / total, accuracy: 1e-6,
                           "Weight \(i) is not the normalized Gaussian at sigma \(sigma)")
        }
        let sum = Double(weights[0]) + 2 * weights.dropFirst().reduce(0) { $0 + Double($1) }
        XCTAssertEqual(sum, 1, accuracy: 1e-6, "The full kernel must sum to 1 or the image changes brightness")
    }

    /// The cap is a real limit rather than a defensive one — `Blur` says so — so it is asserted rather
    /// than left to be discovered as a silently different picture at radius 400.
    func testTheTapCountIsCappedAndAZeroRadiusIsASingleCentreTap() {
        XCTAssertEqual(Effect.blur(Effect.Blur(radius: 4000)).weights.count, Effect.maxBlurTaps + 1)
        XCTAssertEqual(Effect.blur(Effect.Blur(radius: 0)).weights, [1])
        XCTAssertEqual(Effect.blur(Effect.Blur(radius: -3)).weights, [1], "A negative radius is not a mirror")
    }

    // MARK: - (2b) Bloom

    /// Nothing below the threshold glows, and the pixels that do glow are the bright ones — the whole
    /// of what a threshold means, asserted on a fixture where the answer is known by construction.
    func testBloomLightsOnlyWhatIsAboveItsThreshold() {
        // A dark field with one bright square: Lum(0.16) is well under the threshold, Lum(0.94) well over.
        var bytes = flatBytes(40, 40, 40)
        for y in 24..<40 {
            for x in 24..<40 {
                let offset = (x + y * Self.side) * 4
                for channel in 0..<3 { bytes[offset + channel] = 240 }
            }
        }
        let out = cpu(.bloom(Effect.Bloom(threshold: 0.5, radius: 5, intensity: 1)), bytes)

        XCTAssertEqual(pixel(out, 4, 4), pixel(bytes, 4, 4),
                       "A corner far from anything bright must be untouched. Got \(pixel(out, 4, 4))")
        XCTAssertGreaterThan(pixel(out, 21, 32)[0], pixel(bytes, 21, 32)[0],
                             "Three pixels outside the bright square must have picked up glow")
    }

    /// **A glow reaches outside the coverage that emitted it**, which is the reason bloom is allowed to
    /// change alpha at all: confined to its own silhouette it would be a brightness adjustment.
    func testBloomSpreadsLightBeyondTheAlphaThatEmittedIt() {
        let bytes = squareBytes(inset: 24, value: 255)
        let out = cpu(.bloom(Effect.Bloom(threshold: 0.2, radius: 6, intensity: 1)), bytes)
        XCTAssertEqual(pixel(bytes, 21, Self.side / 2)[3], 0, "Fixture check: that pixel is empty to begin with")
        XCTAssertGreaterThan(pixel(out, 21, Self.side / 2)[3], 0,
                             "The glow must have added coverage where there was none")
    }

    /// Addition can push a channel above the coverage carrying it, and the combine pass re-imposes
    /// `rgb <= a` for that reason. A violation would not show here — it would show much later, as an
    /// unpremultiply above 1 in whatever read the texture next.
    func testBloomLeavesAValidPremultipliedImage() {
        let out = cpu(.bloom(Effect.Bloom(threshold: 0.1, radius: 8, intensity: 3)), squareBytes(inset: 20))
        for pixelStart in stride(from: 0, to: out.count, by: 4) {
            let alpha = out[pixelStart + 3]
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(out[pixelStart + channel], alpha,
                                         "Bloom at intensity 3 produced rgb above alpha at byte \(pixelStart)")
            }
        }
    }

    /// Bloom is four passes and blur is two, which is the shape §7's "nearly free once blur exists"
    /// describes — and the assertion that catches someone giving bloom its own kernel later.
    func testBloomIsFourPassesOverTheSameKernelBlurUses() {
        let passes = Effect.bloom(Effect.Bloom()).passes
        XCTAssertEqual(passes.count, 4)
        XCTAssertEqual(passes.map(\.kind), [8, 7, 7, 9], "threshold, blur, blur, combine")
        XCTAssertEqual(passes[1].params.offsetX, 1)
        XCTAssertEqual(passes[1].params.offsetY, 0)
        XCTAssertEqual(passes[2].params.offsetX, 0)
        XCTAssertEqual(passes[2].params.offsetY, 1)
    }

    // MARK: - (2c) The arithmetic measured against mathematics rather than against itself
    //
    // **Why this section exists, in one sentence: nothing above it can say the blur is a Gaussian.**
    //
    // Everything above is one of three kinds, and all three share a hole. The backend sweep compares
    // `Composite.metal` against `EffectReference` — but both are handed the *same* Swift-resolved
    // `kindCode`, `params`, `lookupTable`, `passes` and `weights`, so a mistake in that resolution is
    // made identically on both sides and the sweep stays green; that is the blind spot `Effect.swift`'s
    // header names. `testTheResolvedWeightsAre…` re-types `gaussianHalfKernel`'s own formula in the
    // test, which catches a transcription slip and not a conceptual error, because one author wrote
    // both. And the geometric properties — the outer-product impulse check, the one-axis check — are
    // stated against `Effect.weights` and run on the CPU reference alone, so they never reach the
    // shader's arithmetic at all.
    //
    // The four cases below close that. Each builds its expectation here from `exp(-d²/2σ²)`, with no
    // reference to `Effect.weights` and no assumption about either backend's structure, and runs
    // **both** backends against it — so the shader is measured against mathematics rather than against
    // the Swift twin that shares its blind spot. σ is the one input they still take on trust, and the
    // note below says why that is a convention no test can derive.

    /// **Why σ = `radius / 3`, recorded here because — alone among this project's effect claims — it
    /// cannot be checked against a published document.**
    ///
    /// The sibling file's spot checks all appeal to a spec: CSS Filter Effects for brightness and
    /// contrast, W3C Compositing and Blending Level 1 for `Lum`, the standard recursive Bayer matrix for
    /// the ordered screen. A Gaussian blur has no such spec. "Radius" is a word from a UI, not from
    /// mathematics — a true Gaussian has infinite support and no radius at all — so every application
    /// invents its own map from the artist's number to σ, and there is no external authority to be right
    /// or wrong against.
    ///
    /// `radius / 3` is the conventional choice, for the reason the three-sigma rule gives: 99.73% of a
    /// Gaussian's mass lies within ±3σ, so truncating the kernel at the radius the artist asked for
    /// discards about 0.27% — under one part in 255, and so below a channel step at 8 bits. A larger
    /// divisor truncates visibly; a smaller one spends taps on weights that quantize to zero.
    ///
    /// So the tests below take σ as an input exactly as `Effect` does, and prove everything downstream:
    /// that the shape really is `exp(-d²/2σ²)`, that it is normalized, that two 1D passes really do
    /// compose into that 2D kernel, and that both backends produce it.
    private static let sigmaPerRadius = 1.0 / 3.0

    /// **`.toNearestOrEven`, the rule Metal's float→unorm8 write uses** — `EffectReference.quantize`
    /// argues it. A reference that rounded halves the other way would report a spurious delta of 1 on
    /// every exactly-half value, which is a property of the output format and not of the formula under
    /// test.
    private func quantized(_ value: Double) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded(.toNearestOrEven))
    }

    /// The truncated 2D Gaussian, normalized over its own support — **written out here from the
    /// exponential, sharing nothing with `Effect.gaussianHalfKernel` but σ.**
    ///
    /// Note what is deliberately *not* assumed: this is a genuine 2D kernel over `(i, j)`, built from
    /// `exp(-(i² + j²) / 2σ²)` and normalized as a square, with no 1D kernel and no outer product
    /// anywhere in it. That it factors into two 1D Gaussians is the mathematical fact under
    /// `Effect.Blur`'s two-pass design; the tests below are what check the code exploits it correctly
    /// rather than merely claiming to.
    private func idealGaussian2D(radius: Double) -> (kernel: [[Double]], taps: Int) {
        let taps = Int(radius.rounded())
        let sigma = radius * Self.sigmaPerRadius
        let denominator = 2 * sigma * sigma
        var kernel = [[Double]](repeating: [Double](repeating: 0, count: 2 * taps + 1),
                                count: 2 * taps + 1)
        var total = 0.0
        for j in -taps...taps {
            for i in -taps...taps {
                let value = exp(-Double(i * i + j * j) / denominator)
                kernel[j + taps][i + taps] = value
                total += value
            }
        }
        for j in kernel.indices { for i in kernel[j].indices { kernel[j][i] /= total } }
        return (kernel, taps)
    }

    /// One clamp-to-edge texel fetch in `[0, 1]`, written here rather than shared, so the reference and
    /// the thing it references cannot agree by sharing a helper.
    private func clampedTexel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> SIMD4<Double> {
        let cx = min(max(x, 0), Self.side - 1), cy = min(max(y, 0), Self.side - 1)
        let offset = (cx + cy * Self.side) * 4
        return SIMD4<Double>(Double(bytes[offset]), Double(bytes[offset + 1]),
                             Double(bytes[offset + 2]), Double(bytes[offset + 3])) / 255
    }

    /// **The independent transcription of the algorithm: a direct `O(n²)` 2D convolution.** Slow,
    /// obviously correct, and structurally nothing like the code it checks — one pass instead of two, a
    /// square kernel instead of a line, `Double` instead of `Float`, and no intermediate buffer at all
    /// and therefore no ping-pong to get wrong.
    ///
    /// Clamping is applied per axis, which is what makes the comparison exact rather than approximate:
    /// a clamped separable pair expands to `Σᵢⱼ w[i]·w[j]·f(clamp(x+i), clamp(y+j))`, which is this sum.
    /// So the two must agree at the border for the same reason they agree in the interior, and a
    /// convention mismatch — one side clamping, the other reading transparent black — would show as a
    /// dark band `radius` wide rather than as a rounding difference.
    private func directConvolution2D(_ bytes: [UInt8], radius: Double) -> [UInt8] {
        let (kernel, taps) = idealGaussian2D(radius: radius)
        var result = bytes
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                var sum = SIMD4<Double>(repeating: 0)
                for j in -taps...taps {
                    for i in -taps...taps {
                        sum += clampedTexel(bytes, x + i, y + j) * kernel[j + taps][i + taps]
                    }
                }
                let offset = (x + y * Self.side) * 4
                for channel in 0..<4 { result[offset + channel] = quantized(sum[channel]) }
            }
        }
        return result
    }

    /// Both backends, or the CPU alone where there is no Metal — so every case below states its claim
    /// about the shader and still runs somewhere without a GPU.
    private func bothBackends(_ effect: Effect, _ bytes: [UInt8]) -> [(String, [UInt8])] {
        var backends: [(String, [UInt8])] = [("cpu", cpu(effect, bytes))]
        if let gpu = MetalEffectEngine.shared?.apply(effect, to: bytes, width: Self.side, height: Self.side) {
            backends.append(("gpu", gpu))
        }
        return backends
    }

    /// **Blur one white pixel on black, and the output *is* the kernel.**
    ///
    /// The strongest single statement in the file, because the read-out is direct: no fitting, no
    /// statistic, no property that many wrong kernels would also satisfy. The bytes at `(±i, ±j)` around
    /// the impulse are the 2D kernel the pipeline actually applied, times 255, and they are compared
    /// against `exp(-(i² + j²)/2σ²)` normalized in this file. Pass structure, ping-pong slot choice, tap
    /// offsets, edge handling and normalization all sit upstream of that number, so every one of them is
    /// under test at once — against mathematics, not against a second copy of the same mistake.
    ///
    /// Sister to `testATwoPassBlurOfAnImpulseIsTheOuterProduct…`, and not a duplicate of it: that one
    /// asks whether the pipeline applied the weights `Effect` resolved, this one asks whether those
    /// weights are a Gaussian. Both can pass while the other fails.
    ///
    /// **Measured maximum channel deviation is recorded in the activity; the bound is 1 because that is
    /// what the arithmetic can produce and no more.** The separable pair writes its intermediate to
    /// RGBA8, so an impulse is quantized twice on the way through (the sister test argues why that
    /// intermediate is deliberate) where this reference rounds once. Larger radii measure *smaller*
    /// deviations, not larger, because the peak is lower and one rounding is a smaller share of it.
    func testTheImpulseResponseIsTheGaussianComputedFromFirstPrinciples() {
        var table: [String] = []
        for radius in [2.0, 3.0, 4.0, 6.0] {
            let effect = Effect.blur(Effect.Blur(radius: radius))
            let (kernel, taps) = idealGaussian2D(radius: radius)
            let centre = (x: Self.side / 2, y: Self.side / 2)
            let input = impulseBytes(at: centre)

            for (backend, out) in bothBackends(effect, input) {
                var worst = 0, worstAt = "-"
                for j in -taps...taps {
                    for i in -taps...taps {
                        let expected = Int(quantized(kernel[j + taps][i + taps]))
                        let got = pixel(out, centre.x + i, centre.y + j)
                        for channel in 0..<4 where abs(got[channel] - expected) > worst {
                            worst = abs(got[channel] - expected)
                            worstAt = "(\(i),\(j))c\(channel) got \(got[channel]) want \(expected)"
                        }
                    }
                }
                table.append("r\(Int(radius))/\(backend) \(worst)")
                XCTAssertLessThanOrEqual(worst, 1,
                                         "The \(backend) blur of an impulse at radius \(radius) is not the Gaussian this test computed from exp(-d²/2σ²): worst \(worstAt)")

                // The kernel has finite support, so the impulse must not have reached past it. A blur
                // that read one tap too far would still look like a blur and would still normalize.
                for step in [taps + 1, taps + 2] {
                    XCTAssertEqual(pixel(out, centre.x + step, centre.y)[3], 0,
                                   "\(backend) at radius \(radius) spread the impulse \(step) px horizontally, past its \(taps)-tap support")
                    XCTAssertEqual(pixel(out, centre.x, centre.y + step)[3], 0,
                                   "\(backend) at radius \(radius) spread the impulse \(step) px vertically, past its \(taps)-tap support")
                }
            }
        }
        XCTContext.runActivity(named: "[multipass] impulse vs first-principles 2D Gaussian, max channel delta: \(table.joined(separator: " · "))") { _ in }
    }

    /// **The separable pair against a direct 2D convolution, over a real image.**
    ///
    /// A separable blur equals the 2D convolution *by construction* — that is the theorem the two-pass
    /// design rests on — so a disagreement here is not a tolerance question, it means the pass structure
    /// is wrong: a dropped pass, a second pass on the wrong axis, an intermediate read from the wrong
    /// ping-pong slot, or a step that is not one texel. The impulse test says the kernel is right at one
    /// pixel; this says the machine applies it at all 4096, over a fixture where every tap lands on a
    /// different value and across an edge band where the clamp convention has to hold.
    ///
    /// **Measured maximum channel delta is 1, and its whole source is the intermediate**: the app
    /// quantizes to RGBA8 between the two 1D passes, this reference accumulates in `Double` and
    /// quantizes once. One rounding of difference is exactly what is measured, and it is the same bound
    /// the blend modes and the grades hold to — the project's number rather than one picked here.
    func testTheSeparablePairEqualsADirect2DConvolution() {
        let bytes = spectrumBytes()
        var table: [String] = []
        for radius in [2.0, 3.0, 5.0] {
            let reference = directConvolution2D(bytes, radius: radius)
            for (backend, out) in bothBackends(.blur(Effect.Blur(radius: radius)), bytes) {
                let delta = maxChannelDelta(out, reference)
                table.append("r\(Int(radius))/\(backend) \(delta)")
                XCTAssertLessThanOrEqual(delta, 1,
                                         "The \(backend) two-pass blur at radius \(radius) differs from a direct 2D convolution by \(delta), past the one rounding its RGBA8 intermediate can explain. This measures the pass structure, not the kernel")
            }
        }
        XCTContext.runActivity(named: "[multipass] separable vs direct 2D, max channel delta: \(table.joined(separator: " · "))") { _ in }
    }

    /// **Bloom's threshold ramp, `(Lum(c) − threshold) / (1 − threshold)`, against hand-computed bytes.**
    ///
    /// Everything else about bloom in this file is qualitative — a dark corner stays untouched, a bright
    /// square glows — and qualitative properties do not pin a formula. Dividing by `threshold`, not
    /// dividing at all, or reading `Lum` off the premultiplied texel instead of the colour all still
    /// darken corners and brighten squares. So the ramp gets numbers.
    ///
    /// **Radius 0 is what makes those numbers hand-computable**: both backends collapse a zero-tap blur
    /// to a straight copy, so the four passes reduce to threshold-then-add. **Alpha is 100 rather than
    /// 255 for the same reason** — it leaves the combine room to add the glow without saturating, so the
    /// alpha channel reads out `round(100 · w)` directly and the weight is observed rather than
    /// inferred.
    ///
    /// Worked by hand at `threshold = 0.4`, `intensity = 1`, with `Lum = 0.3r + 0.59g + 0.11b` taken on
    /// the unpremultiplied colour `c = premultiplied / alpha`:
    ///
    ///     in (premul)         c              Lum     w=(Lum-0.4)/0.6   glow=round(w·in)   out=in+glow
    ///     (20, 30, 10, 100)   (.20,.30,.10)  0.248   0 (clamped)       (0, 0, 0, 0)       (20, 30, 10, 100)
    ///     (40, 40, 40, 100)   (.40,.40,.40)  0.400   0 (the foot)      (0, 0, 0, 0)       (40, 40, 40, 100)
    ///     (40, 70, 20, 100)   (.40,.70,.20)  0.555   0.2583            (10, 18, 5, 26)    (50, 88, 25, 126)
    ///     (100,100,100,100)   (1, 1, 1)      1.000   1 (the top)       (100,100,100,100)  (200,200,200,200)
    ///
    /// The third row is the load-bearing one: its three channels differ, so all three `Lum` coefficients
    /// do distinct work. Swapping 0.3 and 0.59 gives Lum 0.468 and an alpha of 111 rather than 126;
    /// dividing by 1 instead of `1 − threshold` gives 115 or 116; dividing by `threshold` saturates to
    /// 255. The last row pins the top of the ramp at exactly 1 and the first two pin its foot at exactly
    /// 0, so the four points determine the affine map uniquely.
    func testBloomsThresholdRampMatchesHandComputedValues() {
        let cases: [(String, [UInt8], [Int])] = [
            ("belowTheThreshold", [20, 30, 10, 100], [20, 30, 10, 100]),
            ("exactlyAtIt",       [40, 40, 40, 100], [40, 40, 40, 100]),
            ("partWayUpTheRamp",  [40, 70, 20, 100], [50, 88, 25, 126]),
            ("fullWhite",     [100, 100, 100, 100], [200, 200, 200, 200]),
        ]
        let effect = Effect.bloom(Effect.Bloom(threshold: 0.4, radius: 0, intensity: 1))
        var table: [String] = []
        for (name, input, expected) in cases {
            let bytes = flatBytes(input[0], input[1], input[2], input[3])
            for (backend, out) in bothBackends(effect, bytes) {
                let got = pixel(out, Self.side / 2, Self.side / 2)
                table.append("\(name)/\(backend) \(got.map(String.init).joined(separator: ","))")
                XCTAssertEqual(got, expected,
                               "\(name) on the \(backend): \(input) came out \(got), not the \(expected) the ramp (Lum − 0.4)/0.6 gives")
            }
        }
        XCTContext.runActivity(named: "[multipass] bloom threshold ramp: \(table.joined(separator: " · "))") { _ in }
    }

    /// Bloom rewritten end to end: bright pass, direct 2D blur, additive combine. Used by the test
    /// below — three stages rather than four, its own blur, `Double` throughout, and the effect's
    /// original input held in a local rather than in a texture bound alongside a ping-pong.
    private func independentBloom(_ bytes: [UInt8], threshold: Double, radius: Double,
                                  intensity: Double) -> [UInt8] {
        var bright = bytes
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let offset = (x + y * Self.side) * 4
                let source = clampedTexel(bytes, x, y)
                guard source.w > 0 else {
                    for channel in 0..<4 { bright[offset + channel] = 0 }
                    continue
                }
                let colour = SIMD3<Double>(min(source.x / source.w, 1), min(source.y / source.w, 1),
                                           min(source.z / source.w, 1))
                let lum = 0.3 * colour.x + 0.59 * colour.y + 0.11 * colour.z
                let weight = min(max((lum - threshold) / max(1 - threshold, 1e-4), 0), 1)
                for channel in 0..<4 { bright[offset + channel] = quantized(source[channel] * weight) }
            }
        }

        let glow = directConvolution2D(bright, radius: radius)
        var result = bytes
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let offset = (x + y * Self.side) * 4
                let base = clampedTexel(bytes, x, y), light = clampedTexel(glow, x, y)
                let alpha = min(max(base.w + light.w * intensity, 0), 1)
                for channel in 0..<3 {
                    let value = min(max(base[channel] + light[channel] * intensity, 0), 1)
                    result[offset + channel] = quantized(min(value, alpha))
                }
                result[offset + 3] = quantized(alpha)
            }
        }
        return result
    }

    /// **The whole four-pass bloom against that independent transcription.**
    ///
    /// The one case that exercises the multi-pass machine end to end against something that is not it.
    /// The part that matters most is the last stage: the app's combine reads the effect's *original*
    /// input from a texture bound for the whole effect while the other three passes ping-pong between
    /// two scratch textures, and a bug there — combining against the wrong buffer, or against a scratch
    /// slot that pass 2 had already overwritten — produces a plausible picture that no self-comparison
    /// can see. A transcription holding the original in a local variable has no way to make the same
    /// mistake.
    ///
    /// **The bound is stated per case, and the amplifying one is 2 rather than 1 for a reason that is
    /// arithmetic and not a formula disagreement**: the app quantizes three times along the glow's path
    /// (threshold, then each 1D pass) where this reference quantizes twice, and the combine then scales
    /// that difference by `intensity`. At intensity ≤ 1 it measures 1; at 1.6 it measures 2, which is
    /// 1.6 roundings rounded up. Recording it as one number would have meant either a false failure or a
    /// tolerance loose enough to hide a real one.
    func testTheWholeBloomMatchesAnIndependentTranscription() {
        let bytes = spectrumBytes()
        let cases: [(threshold: Double, radius: Double, intensity: Double, bound: Int)] = [
            (0.4, 3, 1.0, 1),
            (0.6, 2, 0.8, 1),
            (0.15, 5, 1.6, 2),
        ]
        var table: [String] = []
        for (threshold, radius, intensity, bound) in cases {
            let reference = independentBloom(bytes, threshold: threshold, radius: radius, intensity: intensity)
            let effect = Effect.bloom(Effect.Bloom(threshold: threshold, radius: radius, intensity: intensity))
            for (backend, out) in bothBackends(effect, bytes) {
                let delta = maxChannelDelta(out, reference)
                table.append("t\(threshold)r\(Int(radius))i\(intensity)/\(backend) \(delta)")
                XCTAssertLessThanOrEqual(delta, bound,
                                         "The \(backend) bloom at threshold \(threshold), radius \(radius), intensity \(intensity) differs from an independently written bloom by \(delta), past the \(bound) its extra quantization can explain")
            }
        }
        XCTContext.runActivity(named: "[multipass] whole bloom vs independent transcription, max channel delta: \(table.joined(separator: " · "))") { _ in }
    }

    // MARK: - (3) The wrapper: identity and coverage

    func testEveryMultiPassEffectAtItsIdentityParametersReturnsItsInput() {
        let bytes = spectrumBytes()
        for (name, effect) in Self.identities {
            XCTAssertEqual(maxChannelDelta(cpu(effect, bytes), bytes), 0,
                           "\(name) must be the identity, byte for byte")
        }
    }

    func testEveryMultiPassEffectAtItsIdentityParametersReturnsItsInputOnTheGPUToo() throws {
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        for (name, effect) in Self.identities {
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            XCTAssertLessThanOrEqual(maxChannelDelta(gpu, bytes), Self.tolerance,
                                     "\(name) must be the identity on the GPU too")
        }
    }

    /// **`reshapesCoverage` is asserted in both directions, which is the point of it being a property
    /// rather than a comment.** Every grade is swept for byte-exact alpha and must not move; blur and
    /// bloom are swept on a silhouette and must. A ninth grade that quietly started reshaping coverage
    /// fails the first half; a blur that stopped fails the second.
    func testTheCoverageFlagMatchesWhatTheEffectsActuallyDo() {
        let silhouette = squareBytes(inset: 16)
        let grades: [Effect] = [
            .levels(Effect.Levels(inputBlack: 0.1, inputWhite: 0.9, gamma: 1.4)),
            .brightnessContrast(Effect.BrightnessContrast(brightness: 1.3, contrast: 1.4)),
            .hsvShift(Effect.HSVShift(hueDegrees: 44, saturation: 1.3, value: 0.9)),
            .gradientMap(Effect.GradientMap(mix: 1)),
            .chromaticAberration(Effect.ChromaticAberration(offsetX: 2, offsetY: 1)),
            .posterize(Effect.Posterize(levels: 3, screen: .ordered, screenStrength: 1)),
            .noise(Effect.Noise(amount: 0.4, seed: 3)),
        ]
        for effect in grades {
            XCTAssertFalse(effect.reshapesCoverage, "\(effect.displayName) declares itself a grade")
            let out = cpu(effect, silhouette)
            let moved = stride(from: 3, to: silhouette.count, by: 4).first { out[$0] != silhouette[$0] }
            XCTAssertNil(moved, "\(effect.displayName) declares it does not reshape coverage but changed alpha at byte \(moved ?? -1)")
        }

        for (name, effect) in Self.sweep {
            XCTAssertTrue(effect.reshapesCoverage, "\(name) must declare that it reshapes coverage")
            let out = cpu(effect, silhouette)
            let moved = stride(from: 3, to: silhouette.count, by: 4).first { out[$0] != silhouette[$0] }
            XCTAssertNotNil(moved, "\(name) declares it reshapes coverage but left every alpha byte alone")
        }
    }

    func testFullyTransparentPixelsStayTransparentBlack() {
        let bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for (name, effect) in Self.sweep {
            XCTAssertEqual(cpu(effect, bytes), bytes, "\(name) must leave an empty buffer empty")
        }
    }

    // MARK: - (4) Sobel — LAYER_COMPOSITING.md §7's "3×3 gradient in x and y, then magnitude"
    //
    // **Defence (a): an impulse response checked against mathematics.** Sobel is a fixed published
    // 3×3 stencil with a closed-form response, so this is genuinely independent of the implementation
    // rather than a same-author re-derivation: the expected bytes below are computed from the published
    // Gx/Gy matrices and the divisor Effect.swift's `params` comment derives, not from reading
    // `EffectKernels.sobel` or `Composite.metal`'s `sobel`. (b) is unavailable (no separable form in
    // this contract); (c) is meaningless (no radius); (d) would be a 9-tap transcription by the same
    // hand that wrote the 9 constants under test, which is weak in exactly the way (a) is not.

    /// **The premise, stated before the arithmetic**: the impulse fixture really is one bright pixel
    /// among zero, not an image that happens to be uniform. A test that skipped this and still passed
    /// would be evidence of nothing — the failure this project has already shipped once.
    func testSobelImpulsePremiseIsGenuinelyAnImpulse() {
        let centre = (x: Self.side / 2, y: Self.side / 2)
        let input = impulseBytes(at: centre)
        XCTAssertEqual(pixel(input, centre.x, centre.y), [255, 255, 255, 255], "Fixture check: the centre must be opaque white")
        XCTAssertEqual(pixel(input, centre.x + 1, centre.y), [0, 0, 0, 0], "Fixture check: its neighbour must be fully transparent, or every position below is trivially the same value")
    }

    /// **The hand-worked table**, computed from the published stencils and stated as literals so a
    /// uniformly-wrong implementation cannot pass by agreeing with itself:
    ///
    ///     Gx = [[-1,0,1],[-2,0,2],[-1,0,1]]   Gy = [[-1,-2,-1],[0,0,0],[1,2,1]]   (y downward)
    ///
    /// For a unit impulse at the origin, `magnitude = sqrt(Gx² + Gy²)` at offset `(dx, dy)` is EXACTLY:
    ///     (0,0) = 0 ; (±1,0) = 2 ; (0,±1) = 2 ; (±1,±1) = √2 ≈ 1.41421356 ; |dx|>1 or |dy|>1 = 0.
    ///
    /// **The divisor is `D = sqrt(20) ≈ 4.47213595`** — the true maximum of `sqrt(Gx² + Gy²)` over all
    /// binary 3×3 patterns (attained at Gx=2, Gy=4, a diagonal step; `Effect.params`'s comment records
    /// the enumeration this came from), chosen because it never clips, unlike D=4. Divided through and
    /// quantized `.toNearestOrEven`:
    ///     centre:        0 / 4.47213595 = 0            → byte 0
    ///     edge-centres:  2 / 4.47213595 = 0.4472136     → 0.4472136 × 255 = 114.0046 → byte 114
    ///     corners:  1.41421356 / 4.47213595 = 0.3162278 → 0.3162278 × 255 = 80.6381  → byte 81
    ///
    /// What this table discriminates from a wrong stencil: Prewitt gives edge-centres 1 and corners
    /// √2 (corners LARGER, the opposite ordering); Scharr gives 10 and √18; a Gy accidentally equal to
    /// Gx gives 2.83/0/1.41. The edge:corner ratio (√2 for Sobel, 0.707 for Prewitt, 2.357 for Scharr)
    /// identifies the operator on its own. What it cannot discriminate — a full Gx↔Gy transpose or any
    /// sign flip — is genuinely unobservable in a magnitude-only Sobel, so it needs no test.
    ///
    /// **`input: .ink` rather than the default, and the change is what this file could not see.** In
    /// that mode the magnitude *is* the coverage, so one byte answers for all four channels and the
    /// table above is the whole output. Under `.backdrop` the alpha is the source's own coverage
    /// instead — and on this fixture the source is transparent everywhere but one pixel, which is
    /// exactly why an impulse could never have caught the alpha bug the owner found on a screen.
    /// `testSobelsTwoAlphaRulesOverAnOpaqueStepEdge` is the fixture that can.
    func testSobelImpulseMatchesTheKnownGradientKernels() {
        let centre = (x: Self.side / 2, y: Self.side / 2)
        let input = impulseBytes(at: centre)
        let expected: [(dx: Int, dy: Int, byte: Int)] = [
            (0, 0, 0),
            (1, 0, 114), (-1, 0, 114), (0, 1, 114), (0, -1, 114),
            (1, 1, 81), (1, -1, 81), (-1, 1, 81), (-1, -1, 81),
        ]
        var table: [String] = []
        for (backend, out) in bothBackends(.sobel(Effect.Sobel(input: .ink)), input) {
            var worst = 0
            for (dx, dy, want) in expected {
                let got = pixel(out, centre.x + dx, centre.y + dy)
                for channel in 0..<4 {
                    worst = max(worst, abs(got[channel] - want))
                    XCTAssertLessThanOrEqual(abs(got[channel] - want), 1,
                                             "\(backend) Sobel at (\(dx),\(dy)) channel \(channel): got \(got[channel]), the Gx/Gy stencils give \(want)")
                }
            }
            // Finite support: the stencil is 3×3, so nothing past radius 1 may have moved.
            for step in [2, 3] {
                XCTAssertEqual(pixel(out, centre.x + step, centre.y), [0, 0, 0, 0],
                               "\(backend) Sobel reached \(step)px horizontally, past its 3×3 support")
                XCTAssertEqual(pixel(out, centre.x, centre.y + step), [0, 0, 0, 0],
                               "\(backend) Sobel reached \(step)px vertically, past its 3×3 support")
            }
            table.append("\(backend) \(worst)")
        }
        XCTContext.runActivity(named: "[sobel] impulse vs Gx/Gy first principles, max channel delta: \(table.joined(separator: " · "))") { _ in }
    }

    /// A constant field has zero gradient everywhere a differencing stencil can reach it, including the
    /// border — clamp-to-edge repeats the same value, so the difference stays zero there too. The
    /// analogue of `testABlurOfAFlatColourIsThatColourIncludingAtTheBorder`, but Sobel's identity output
    /// is black rather than the input colour, since the effect replaces the image with an edge map.
    ///
    /// **Both modes, because the identity output is where they differ and EFFECT_BACKDROP.md §2.2 got
    /// that wrong.** §2.2 claimed an opaque backdrop made flat regions opaque black on its own; the
    /// kernel emitted `(m, m, m, m)`, so it made them *transparent*, and the artist saw whatever was
    /// behind the composite. This is that claim as an assertion: it is true of `.backdrop` now, and it
    /// was never true of `.ink` and still is not.
    func testSobelOfAFlatColourIsBlackEverywhereIncludingAtTheBorder() {
        let bytes = flatBytes(90, 160, 40)
        for (backend, out) in bothBackends(.sobel(Effect.Sobel(input: .ink)), bytes) {
            XCTAssertEqual(out, [UInt8](repeating: 0, count: bytes.count),
                           "\(backend): under `.ink` the magnitude is the coverage, so a flat field is "
                           + "transparent black — the paper shows through it, which is the whole look "
                           + "that mode exists to offer")
        }
        var opaqueBlack = [UInt8](repeating: 0, count: bytes.count)
        for pixel in stride(from: 3, to: opaqueBlack.count, by: 4) { opaqueBlack[pixel] = 255 }
        for (backend, out) in bothBackends(.sobel(Effect.Sobel()), bytes) {
            XCTAssertEqual(out, opaqueBlack,
                           "\(backend): under the ruled `.backdrop` default the coverage it was handed "
                           + "comes back, so a flat field is OPAQUE black — an edge detector's ground. "
                           + "It was RGBA (0,0,0,0), and over the paper that is a hole in the canvas")
        }
    }

    /// **The two alpha rules side by side over one fixture, which is the test that was missing.**
    ///
    /// An opaque vertical step — black left half, white right half — is the smallest image in which
    /// "bright edges on black" is a sentence about bytes. Every earlier Sobel fixture here was either
    /// flat or an impulse on transparency, and on both of those `(m, m, m, m)` and a correct opaque
    /// edge map agree everywhere it was checked. That is how the defect the owner reported cleared a
    /// full suite: *"weird, sobel should be black mostly but right now its grey"*.
    ///
    /// The magnitude is the same in both modes and is computed from the published stencils rather than
    /// from either kernel: across the seam `Gx = 4`, `Gy = 0`, and `4 / sqrt(20) = 0.894427` → byte 228.
    /// Only the alpha differs, and only by which of the two the mode asked for.
    func testSobelsTwoAlphaRulesOverAnOpaqueStepEdge() {
        let side = Self.side
        var step = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let offset = (x + y * side) * 4
                let value: UInt8 = x < side / 2 ? 0 : 255
                step[offset] = value; step[offset + 1] = value; step[offset + 2] = value
                step[offset + 3] = 255
            }
        }
        let seam = side / 2 - 1

        for (backend, out) in bothBackends(.sobel(Effect.Sobel()), step) {
            XCTAssertEqual(pixel(out, 4, 32), [0, 0, 0, 255],
                           "\(backend) `.backdrop`, flat black far from the seam: opaque black. "
                           + "Got \(pixel(out, 4, 32))")
            XCTAssertEqual(pixel(out, side - 5, 32), [0, 0, 0, 255],
                           "\(backend) `.backdrop`, flat white far from the seam: opaque black too — a "
                           + "gradient magnitude does not care which flat value it is. Got \(pixel(out, side - 5, 32))")
            let edge = pixel(out, seam, 32)
            XCTAssertEqual(edge[3], 255, "\(backend) `.backdrop`: the edge is opaque. Got \(edge)")
            XCTAssertLessThanOrEqual(abs(edge[0] - 228), 1,
                                     "\(backend) `.backdrop`: 4 / sqrt(20) = 0.894427 → 228. Got \(edge)")
        }

        for (backend, out) in bothBackends(.sobel(Effect.Sobel(input: .ink)), step) {
            XCTAssertEqual(pixel(out, 4, 32), [0, 0, 0, 0],
                           "\(backend) `.ink`, flat: transparent black, byte for byte as it shipped. "
                           + "Got \(pixel(out, 4, 32))")
            let edge = pixel(out, seam, 32)
            XCTAssertLessThanOrEqual(abs(edge[0] - 228), 1,
                                     "\(backend) `.ink`: the same magnitude — the stencil is not what "
                                     + "the mode changes. Got \(edge)")
            XCTAssertEqual(edge[3], edge[0],
                           "\(backend) `.ink`: …and alpha IS that magnitude, which is the rule "
                           + "`(m, m, m, m)` states and the one that must not change. Got \(edge)")
        }
    }

    // MARK: - (5) Sharpen / unsharp — `x + amount·(x − blur_r(x))`
    //
    // **Defence (d): an independent transcription in a different number of stages**, mirroring
    // `independentBloom` below it. The blur half is already proven by (a)/(b) in the impulse and
    // separable-vs-direct tests above; everything NEW here is the combine, and a self-comparison is
    // exactly blind to a combine bug (both backends read the same `original` binding and would combine
    // the same wrong buffer identically). So `independentSharpen` holds the original in a local, runs
    // one direct 2D convolution rather than the app's two 1D passes, and does the algebra once in
    // `Double` — structurally nothing like the three-pass pipeline it checks.

    /// Bloom's independent transcription, restated for sharpen: bright pass replaced by a direct blur,
    /// the additive combine replaced by `original + amount·(original − blurred)`. One convolution stage
    /// against the app's three passes.
    private func independentSharpen(_ bytes: [UInt8], radius: Double, amount: Double) -> [UInt8] {
        let blurred = directConvolution2D(bytes, radius: radius)
        var result = bytes
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let base = clampedTexel(bytes, x, y)
                let blur = clampedTexel(blurred, x, y)
                let out = base + (base - blur) * amount
                let alpha = min(max(out.w, 0), 1)
                let offset = (x + y * Self.side) * 4
                for channel in 0..<3 {
                    let value = min(max(out[channel], 0), 1)
                    result[offset + channel] = quantized(min(value, alpha))
                }
                result[offset + 3] = quantized(alpha)
            }
        }
        return result
    }

    func testTheWholeSharpenMatchesAnIndependentTranscription() {
        let bytes = spectrumBytes()
        // The premise: a fixture that happened to be flat would make the combine's difference zero
        // everywhere and this test would pass no matter what the combine did.
        XCTAssertGreaterThan(Set(stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }).count, 1,
                             "Fixture check: spectrumBytes must vary, or a broken combine cannot be seen")

        let cases: [(radius: Double, amount: Double, bound: Int)] = [
            (2, 0.5, 1),
            (3, 1.0, 1),
            (2, 2.0, 3),
        ]
        var table: [String] = []
        for (radius, amount, bound) in cases {
            let reference = independentSharpen(bytes, radius: radius, amount: amount)
            let effect = Effect.sharpen(Effect.Sharpen(radius: radius, amount: amount))
            for (backend, out) in bothBackends(effect, bytes) {
                let delta = maxChannelDelta(out, reference)
                table.append("r\(Int(radius))a\(amount)/\(backend) \(delta)")
                XCTAssertLessThanOrEqual(delta, bound,
                                         "\(backend) sharpen at radius \(radius), amount \(amount) differs from an independently written sharpen by \(delta), past the \(bound) its extra quantization can explain")
            }
        }
        XCTContext.runActivity(named: "[sharpen] whole sharpen vs independent transcription, max channel delta: \(table.joined(separator: " · "))") { _ in }
    }

    /// **The load-bearing relationship to the existing blur, stated as code rather than as a claim in
    /// a comment.** `Sharpen.weights` must be the exact same call `Effect.blur` makes at the same
    /// radius — not a re-typed formula that happens to agree — which is what would break if the two
    /// derivations were ever allowed to drift apart.
    func testSharpenSharesItsBlurKernelWithBlurAtTheSameRadius() {
        for radius in [0.0, 2.0, 9.0] {
            XCTAssertEqual(Effect.sharpen(Effect.Sharpen(radius: radius, amount: 1.5)).weights,
                           Effect.blur(Effect.Blur(radius: radius)).weights,
                           "sharpen's weights at radius \(radius) must be Effect.blur's own weights, not a re-derivation")
        }
    }

    /// **`amount: −1` reproduces the plain blur byte for byte.** `x + (−1)(x − blur(x)) = blur(x)`
    /// exactly, in float, from two byte-valued operands, and `quantize(blur) = blur` — so this ties the
    /// brand-new combine to the kernel the impulse-response and separable-vs-direct tests above already
    /// proved, and it fails on a swapped operand, a sign flip, a different σ, or a different tap count.
    func testSharpenAtAmountNegativeOneEqualsThePlainBlurByteForByte() {
        let bytes = spectrumBytes()
        for radius in [0.0, 2.0, 6.0] {
            let sharpened = cpu(.sharpen(Effect.Sharpen(radius: radius, amount: -1)), bytes)
            let blurred = cpu(.blur(Effect.Blur(radius: radius)), bytes)
            XCTAssertLessThanOrEqual(maxChannelDelta(sharpened, blurred), 1,
                                     "sharpen(radius: \(radius), amount: -1) must equal blur(radius: \(radius)): x + (-1)(x - blur) = blur algebraically")
        }
    }

    // MARK: - (6) Outline — LAYER_COMPOSITING.md §7's "distance field around alpha"
    //
    // **Defence (c): a hand-computed spot check at the degenerate radius.** At width 1 the painted set
    // is exactly the pixels at Euclidean distance ≤ 1 from the shape and not in it, which is a set to
    // enumerate rather than compute: the four 4-neighbours are painted (d = 1), the four diagonals are
    // not (d = √2 > 1). That is the single input that separates the Euclidean distance this effect
    // implements from the L∞ (Chebyshev) distance a pair of separable max passes would give instead —
    // 4 painted pixels against 8. (a) does not apply (a threshold-then-min-distance is nonlinear, so
    // there is no impulse response); (b) is the question rather than the check (the implementation
    // being separable would BE the L∞ answer, not something to compare against it); (d) — a brute-force
    // scan at a real width like 4–6 — is a good second test but is same-author and cannot identify the
    // metric the way counting 4 against 8 by hand can.

    /// The premise: the fixture is one opaque pixel among transparency, so the ring at distance 1 is a
    /// real boundary a broken outline could get wrong in either direction (painting nothing, or
    /// painting everything within reach).
    func testOutlinePremiseIsGenuinelyAnImpulse() {
        let centre = (x: Self.side / 2, y: Self.side / 2)
        let input = impulseBytes(at: centre)
        XCTAssertEqual(pixel(input, centre.x, centre.y)[3], 255, "Fixture check: the centre must be opaque")
        XCTAssertEqual(pixel(input, centre.x + 1, centre.y)[3], 0, "Fixture check: its neighbour must be transparent")
    }

    /// **The width-1 spot check.** A cross of exactly 4 painted pixels, not a ring of 8 — the signature
    /// a pair of separable max passes cannot produce. Also pins four more Swift-resolution decisions no
    /// backend-parity sweep can see: the centre is unchanged byte-for-byte (the containment rule), a
    /// painted pixel is `round(C·255)` with alpha 255 (catches an unpremultiplied write into a
    /// premultiplied texture), the ring at distance 2 is untouched (finite support), and — separately,
    /// below — an alpha exactly at the threshold resolves the same way on both backends.
    func testOutlineAtWidthOneIsAFourPixelCrossNotAnEightPixelRing() {
        let centre = (x: Self.side / 2, y: Self.side / 2)
        let input = impulseBytes(at: centre)
        let colour = CodableColor(red: 1, green: 0, blue: 0, alpha: 1) // pure red, so a wrong channel is obvious
        let effect = Effect.outline(Effect.Outline(width: 1, color: colour, threshold: 0.5))

        for (backend, out) in bothBackends(effect, input) {
            XCTAssertEqual(pixel(out, centre.x, centre.y), [255, 255, 255, 255],
                           "\(backend): the shape's own pixel must be unchanged — the containment rule")

            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                XCTAssertEqual(pixel(out, centre.x + dx, centre.y + dy), [255, 0, 0, 255],
                               "\(backend) at (\(dx),\(dy)), distance 1: must be painted red, round(C·255) with alpha 255")
            }
            for (dx, dy) in [(1, 1), (1, -1), (-1, 1), (-1, -1)] {
                XCTAssertEqual(pixel(out, centre.x + dx, centre.y + dy), [0, 0, 0, 0],
                               "\(backend) at (\(dx),\(dy)), distance √2 > 1: must be untouched — an 8-pixel ring here would mean L∞, not Euclidean")
            }
            for (dx, dy) in [(2, 0), (0, 2), (2, 2)] {
                XCTAssertEqual(pixel(out, centre.x + dx, centre.y + dy), [0, 0, 0, 0],
                               "\(backend) at (\(dx),\(dy)): a width-1 outline must have finite support")
            }
        }
    }

    /// The binary-with-a-threshold argument LAYER_COMPOSITING.md §6.3 makes for `MaskResolver`: an
    /// alpha sitting exactly on the containment line must resolve the same way everywhere. 128/255 ≈
    /// 0.502 sits just above threshold 0.5, so this pixel is "in the shape" on both backends or the
    /// outline painted around it disagrees about where its own edge is.
    ///
    /// **Observed through a side effect rather than self-reference on purpose.** Asking "is the centre
    /// pixel unchanged" cannot distinguish the two outcomes here: this canvas has no other in-shape
    /// pixel anywhere, so a centre classified "outside" ALSO finds nothing to paint within reach and
    /// is left unchanged too — the same observable result as being classified "inside". Instead this
    /// reads a transparent *neighbour* one pixel away, which is painted if and only if the centre
    /// really did clear the threshold.
    func testOutlineResolvesAnAlphaAtTheThresholdTheSameWayOnBothBackends() {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        let centre = Self.side / 2
        let offset = (centre + centre * Self.side) * 4
        for channel in 0..<3 { bytes[offset + channel] = 128 }
        bytes[offset + 3] = 128
        let effect = Effect.outline(Effect.Outline(width: 1, color: CodableColor(red: 0, green: 1, blue: 0, alpha: 1), threshold: 0.5))

        var painted: [String: Bool] = [:]
        for (backend, out) in bothBackends(effect, bytes) {
            painted[backend] = pixel(out, centre + 1, centre) != [0, 0, 0, 0]
        }
        let values = Set(painted.values)
        XCTAssertEqual(values.count, 1, "The backends disagree about whether alpha 128/255 clears threshold 0.5: \(painted)")
        XCTAssertEqual(painted.values.first ?? false, true,
                       "128/255 ≈ 0.50196 is > threshold 0.5 and must count as in the shape — otherwise both backends could quietly agree on the wrong side")
    }

    // MARK: - The abstraction itself

    /// **`passes[0]` is `kindCode` and `params`, for every effect in the file.** That invariant is what
    /// lets the two older derived values keep the meaning they had before multi-pass existed rather
    /// than becoming vestigial — a one-pass effect is still completely described by them.
    func testPassZeroIsAlwaysTheEffectsOwnKindAndParameters() {
        let everything: [Effect] = [
            .levels(Effect.Levels()), .curves(Effect.Curves()),
            .brightnessContrast(Effect.BrightnessContrast()), .hsvShift(Effect.HSVShift()),
            .gradientMap(Effect.GradientMap()), .chromaticAberration(Effect.ChromaticAberration()),
            .posterize(Effect.Posterize()), .noise(Effect.Noise()),
            .blur(Effect.Blur(radius: 5)), .blur(Effect.Blur(radius: 5, isDirectional: true)),
            .bloom(Effect.Bloom()),
            .sobel(Effect.Sobel()), .sharpen(Effect.Sharpen(radius: 3, amount: 1)),
            .outline(Effect.Outline()),
        ]
        for effect in everything {
            XCTAssertEqual(effect.passes.first, EffectPass(kind: effect.kindCode, params: effect.params),
                           "\(effect.displayName)'s first pass must be its own kind and parameters")
            XCTAssertFalse(effect.passes.isEmpty, "\(effect.displayName) must declare at least one pass")
        }
    }

    /// **A per-pixel effect declares exactly one pass, which is how it goes on costing what it cost.**
    /// The encode path allocates an intermediate only when there is more than one pass, so this is the
    /// assertion standing between the eight cheap effects and a texture allocation they do not need.
    func testEveryPerPixelEffectIsStillExactlyOnePass() {
        let cheap: [Effect] = [
            .levels(Effect.Levels()), .curves(Effect.Curves()),
            .brightnessContrast(Effect.BrightnessContrast()), .hsvShift(Effect.HSVShift()),
            .gradientMap(Effect.GradientMap()), .chromaticAberration(Effect.ChromaticAberration()),
            .posterize(Effect.Posterize()), .noise(Effect.Noise()),
            // Sobel and outline are gathers, not grades, but they are still one dispatch each: neither
            // convolves with `weights`, so both bind the same [1] stub every non-convolving effect does.
            .sobel(Effect.Sobel()), .outline(Effect.Outline()),
        ]
        for effect in cheap {
            XCTAssertEqual(effect.passes.count, 1, "\(effect.displayName) must still be a single dispatch")
            XCTAssertEqual(effect.weights, [1], "\(effect.displayName) convolves nothing and must bind a stub")
        }
    }

    /// Thirteen kernel branches and every one reachable — the assertion that catches a new case copying
    /// an existing case's code, which a parity sweep shows only as one effect quietly rendering as
    /// another. Phase 9c's addition of Sobel, sharpen's combine and outline raised the ceiling from 9
    /// to 12; each of the three is also a gather kind, so a missing entry in either backend's early-out
    /// list (Composite.metal, EffectKernels.swift) renders as the identity rather than failing here —
    /// this test only proves the kind is *reachable*, and the effect-specific tests above are what
    /// would notice a silent identity.
    func testEveryKernelBranchIsReachedThroughSomePassList() {
        let everything: [Effect] = [
            .levels(Effect.Levels()), .brightnessContrast(Effect.BrightnessContrast()),
            .hsvShift(Effect.HSVShift()), .gradientMap(Effect.GradientMap()),
            .chromaticAberration(Effect.ChromaticAberration()), .posterize(Effect.Posterize()),
            .noise(Effect.Noise()), .blur(Effect.Blur(radius: 1)), .bloom(Effect.Bloom()),
            .sobel(Effect.Sobel()), .sharpen(Effect.Sharpen(radius: 1, amount: 1)),
            .outline(Effect.Outline()),
        ]
        XCTAssertEqual(Set(everything.flatMap { $0.passes.map(\.kind) }), Set(0...12),
                       "Every branch of applyEffect must be reachable from some effect's pass list")
    }

    // MARK: - Persistence

    func testBlurAndBloomSurviveAJSONRoundTrip() throws {
        for (name, effect) in Self.sweep {
            let decoded = try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(effect))
            XCTAssertEqual(decoded, effect, "\(name) did not survive encode/decode")
        }
    }

    /// Absence is "saved before this knob existed", not a failure — `FolderManifest.alphaMask`'s recipe,
    /// which these two cases inherit rather than reinvent.
    func testBlurAndBloomWithMissingKeysDecodeIntoTheirDefaults() throws {
        let bareBlur = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"blur"}"#.utf8))
        XCTAssertEqual(bareBlur, .blur(Effect.Blur()))

        let partialBloom = try JSONDecoder().decode(Effect.self,
                                                    from: Data(#"{"kind":"bloom","params":{"radius":3}}"#.utf8))
        XCTAssertEqual(partialBloom, .bloom(Effect.Bloom(threshold: 0.75, radius: 3, intensity: 1)),
                       "A parameter absent from the JSON must fall back to its default, not fail")
    }

    // MARK: - Cost
    //
    // §7 calls blur "moderate" and it is the first effect in this project whose cost is not bounded by
    // the pixel count alone: `2 · (2r + 1)` samples per pixel for a Gaussian. So it gets measured
    // rather than assumed.

    /// **Heavy, and gated for the reason `testMaskedCompositeCostAtCanvasResolution` is gated**: a
    /// canvas-resolution case's memory profile is what pushed an unrelated suite's case from 0.073 s to
    /// 8.98 s when the two shared a runner process, and a full-canvas blur is exactly that shape.
    ///
    /// ```
    /// xcodebuild test … -only-testing:PaintSoftwareUITests/EffectMultiPassLogicTests/testBlurCostAtCanvasResolution \
    ///   PAINT_PERF_HEAVY=1
    /// ```
    ///
    /// **Read the reported numbers and the configuration they were built in — never quote one from a
    /// Debug build.** This project has measured 62× and 440× Debug-to-Release ratios on real loops, and
    /// the CPU reference below is exactly the kind of tight nested loop that produces them. The GPU side
    /// is shader code and is not affected by the Swift optimisation level, but `MetalEffectEngine.apply`
    /// uploads and reads back per call, so the radius-0 row is measured alongside to separate the round
    /// trip from the convolution.
    ///
    /// Ceilings only, an order of magnitude clear of the measurement, in `PerfBaselineTests`' house
    /// style — read the reported numbers, do not tighten these.
    func testBlurCostAtCanvasResolution() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINT_PERF_HEAVY"] != nil,
                          "Heavy: a canvas-resolution blur plus a CPU reference, which destabilises whatever shares the runner process")
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }

        func seconds(_ body: () -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            body()
            return CFAbsoluteTimeGetCurrent() - start
        }
        func buffer(_ side: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            for i in stride(from: 0, to: bytes.count, by: 4) {
                bytes[i] = UInt8((i / 4) % 256)
                bytes[i + 1] = UInt8((i / 4 / side) % 256)
                bytes[i + 2] = 128
                bytes[i + 3] = 255
            }
            return bytes
        }

        let radius16 = Effect.blur(Effect.Blur(radius: 16))
        let radius0 = Effect.blur(Effect.Blur(radius: 0))
        let bloom = Effect.bloom(Effect.Bloom(threshold: 0.5, radius: 16, intensity: 1))

        // 512²: the size both backends are measured at, so the GPU-vs-CPU ratio compares like with like.
        let small = buffer(512)
        _ = engine.apply(radius16, to: small, width: 512, height: 512)   // warm the pipeline and the pool
        let gpuSmall = seconds { _ = engine.apply(radius16, to: small, width: 512, height: 512) }
        let gpuSmallIdentity = seconds { _ = engine.apply(radius0, to: small, width: 512, height: 512) }
        let cpuSmall = seconds { _ = EffectReference.apply(radius16, to: small, width: 512, height: 512) }

        // 2048²: a real canvas, GPU only — the CPU reference at this size is minutes, not seconds.
        let full = buffer(2048)
        _ = engine.apply(radius16, to: full, width: 2048, height: 2048)
        let gpuFull = seconds { _ = engine.apply(radius16, to: full, width: 2048, height: 2048) }
        let gpuFullIdentity = seconds { _ = engine.apply(radius0, to: full, width: 2048, height: 2048) }
        let gpuFullBloom = seconds { _ = engine.apply(bloom, to: full, width: 2048, height: 2048) }

        #if DEBUG
        let configuration = "DEBUG (-Onone) — the CPU row is not a usable number"
        #else
        let configuration = "RELEASE (-O)"
        #endif
        let report = [
            "configuration \(configuration)",
            "gpu512r16 \(Int(gpuSmall * 1000))ms",
            "gpu512r0 \(Int(gpuSmallIdentity * 1000))ms",
            "cpu512r16 \(Int(cpuSmall * 1000))ms",
            "gpu2048r16 \(Int(gpuFull * 1000))ms",
            "gpu2048r0 \(Int(gpuFullIdentity * 1000))ms",
            "gpu2048bloom \(Int(gpuFullBloom * 1000))ms",
            "cpuOverGpu512 \(Int((cpuSmall / max(gpuSmall, 1e-9)).rounded()))x",
        ].joined(separator: " · ")
        XCTContext.runActivity(named: "[multipass] blur cost: \(report)") { _ in }

        XCTAssertLessThan(gpuFull, 5, "A 2048² radius-16 Gaussian, upload and readback included, took \(gpuFull)s. \(report)")
        XCTAssertLessThan(gpuFullBloom, 10, "A 2048² bloom took \(gpuFullBloom)s. \(report)")
    }

}
