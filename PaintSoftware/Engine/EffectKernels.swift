import UIKit

// MARK: - The CPU reference for Tier 3 effects
//
// LAYER_COMPOSITING.md §4.4/§7. The counterpart to `applyEffect` in `Composite.metal`, and the same
// relationship `CoreGraphicsCompositor` has to `compositeOver`: this is the definition, the shader is
// measured against it, and a device with no Metal renders through it.
//
// **What "reference" can and cannot mean here, stated up front, because this is where the project has
// been burned.** For the blend modes, eleven of fourteen Tier 1 cases are Apple's own `CGBlendMode`
// implementations, so a GPU-versus-CPU delta crosses a real framework boundary. **No effect in this
// file has a CoreGraphics primitive at all.** CoreGraphics composites and draws; it does not grade.
// So a parity sweep over these seven compares the app's Metal against the app's Swift — two
// implementations of the same formulas by the same hand — and it is worth exactly what that is worth:
// it catches transcription slips, layout mismatches between `EffectParams` here and in the shader, and
// wrong kind codes, and it says nothing whatever about whether the formula itself is right.
//
// What says that is the other half of `EffectParityLogicTests`: values computed from the published
// definitions and asserted against this file directly. Every effect with a spec (§7's list is mostly
// specless, but Levels, CSS's brightness/contrast, W3C's Lum and the standard Bayer screen are not)
// gets one. Read the two kinds of test as answering two different questions, and never read a green
// sweep as evidence about the third.
//
// One genuine exception, and it is deliberate: **HSV goes through `ColorMath.rgbToHSB`/`hsbToRGB`**,
// the conversion the colour picker already ships, written by someone else before effects existed and
// in `Double` rather than `Float`. That makes HSV's delta the one number in the sweep that compares
// two independently authored implementations.

enum EffectReference {

    /// One effect over one premultiplied RGBA8 buffer, in the app's byte layout — device RGB,
    /// premultiplied last, 8 bits per component, row-major, top-left origin.
    ///
    /// **Every pass in `effect.passes`, in order, each fed the previous one's output** — the same rule
    /// `EffectPipelines.encode` follows on the GPU, and the reason the two can be compared at all. An
    /// effect with one pass runs this loop once and allocates nothing extra, which is the whole of what
    /// "a single-pass effect does not pay for multi-pass" means on this side.
    ///
    /// **A grade copies alpha through unchanged**, and that is the contract rather than an
    /// implementation detail: one that could alter coverage would reshape the artwork it is applied to,
    /// and neither §4.4 wrapper — a stack layer grading the backdrop, or a node grading its slot — has
    /// any business doing that. Blur and bloom are the two effects that *do* reshape coverage, because
    /// that is what they are (`Effect.reshapesCoverage` names them, and `Effect.swift`'s header argues
    /// it); they convolve premultiplied values, so colour and coverage move together.
    ///
    /// Fully transparent pixels come out fully transparent, with colour zeroed, matching the kernel's
    /// early-out. Unpremultiplying at `a == 0` has no answer, and the two backends have to give the
    /// same non-answer.
    static func apply(_ effect: Effect, to bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return bytes }
        let lut = effect.lookupTable
        let weights = effect.weights

        var current = bytes
        for pass in effect.passes {
            current = apply(pass, to: current, original: bytes, lut: lut, weights: weights,
                            width: width, height: height)
        }
        return current
    }

    /// One pass over one buffer. `original` is the effect's own input, unchanged by any earlier pass —
    /// bloom's combine is the one kernel that reads it, and it is passed to every pass rather than
    /// declared per pass so that `EffectPass` stays a kind and a parameter block.
    private static func apply(_ pass: EffectPass, to bytes: [UInt8], original: [UInt8],
                              lut: [UInt8], weights: [Float], width: Int, height: Int) -> [UInt8] {
        let kind = pass.kind, params = pass.params

        // The gather and multi-pass kernels answer for the whole premultiplied pixel — they need the
        // alpha of texels other than this one — so they sit outside the unpremultiply wrapper below
        // rather than inside it.
        switch kind {
        case kChromaticAberration:
            return chromaticAberration(bytes, params: params, width: width, height: height)
        case kBlur1D:
            return blur1D(bytes, params: params, weights: weights, width: width, height: height)
        case kBloomThreshold:
            return bloomThreshold(bytes, params: params, width: width, height: height)
        case kBloomCombine:
            return bloomCombine(bytes, original: original, params: params, width: width, height: height)
        case kSobel:
            return sobel(bytes, params: params, width: width, height: height)
        case kSharpenCombine:
            return sharpenCombine(bytes, original: original, params: params, width: width, height: height)
        case kOutline:
            return outline(bytes, params: params, width: width, height: height)
        default:
            break
        }

        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let pixel = (x + y * width) * 4
                let alpha = Float(bytes[pixel + 3]) / 255
                guard alpha > 0 else {
                    for channel in 0..<4 { result[pixel + channel] = 0 }
                    continue
                }
                let source = SIMD3<Float>(Float(bytes[pixel]) / 255,
                                          Float(bytes[pixel + 1]) / 255,
                                          Float(bytes[pixel + 2]) / 255)
                let colour = clamp(source / alpha)
                let graded = clamp(transform(kind, params, lut, colour, x: x, y: y))
                for channel in 0..<3 {
                    result[pixel + channel] = quantize(graded[channel] * alpha)
                }
                result[pixel + 3] = bytes[pixel + 3]
            }
        }
        return result
    }

    /// The `CGImage` convenience, through exactly the conversions both compositor backends use — the
    /// image is redrawn into the app's byte layout rather than read out of whatever backing store it
    /// arrived with, for the reason `CoreGraphicsCompositor.premultipliedBytes` gives.
    static func apply(_ effect: Effect, to image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let bytes = CoreGraphicsCompositor.premultipliedBytes(image, width: width, height: height) else {
            return nil
        }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: apply(effect, to: bytes, width: width, height: height),
                                                width: width, height: height)
    }

    // MARK: - Kind codes
    //
    // **These must match the `kEffect…` constants in `Composite.metal` and `Effect.kindCode`, case for
    // case.** Three literals in three places with nothing but this comment between them, covered the
    // way the blend-mode codes are: `EffectParityLogicTests` runs every effect through both backends,
    // where a code that disagreed renders as some *other* real effect rather than failing to compile.

    private static let kLookupTable: UInt32 = 0
    private static let kBrightnessContrast: UInt32 = 1
    private static let kHSVShift: UInt32 = 2
    private static let kGradientMap: UInt32 = 3
    private static let kChromaticAberration: UInt32 = 4
    private static let kPosterize: UInt32 = 5
    private static let kNoise: UInt32 = 6
    private static let kBlur1D: UInt32 = 7
    private static let kBloomThreshold: UInt32 = 8
    private static let kBloomCombine: UInt32 = 9
    private static let kSobel: UInt32 = 10
    private static let kSharpenCombine: UInt32 = 11
    private static let kOutline: UInt32 = 12

    // MARK: - The per-pixel transforms
    //
    // Unpremultiplied in, unpremultiplied out, `[0, 1]` on both sides — the same contract
    // `BlendMode.handRolledChannel` has, and for the same reason: it is the only shape in which the
    // arithmetic can be compared with the shader's line for line.

    private static func transform(_ kind: UInt32, _ params: EffectParams, _ lut: [UInt8],
                                  _ c: SIMD3<Float>, x: Int, y: Int) -> SIMD3<Float> {
        switch kind {
        case kLookupTable:
            return SIMD3<Float>(entry(lut, index(c.x), 0), entry(lut, index(c.y), 1), entry(lut, index(c.z), 2))

        case kBrightnessContrast:
            // Contrast then brightness, clamped once at the end — see `Effect.BrightnessContrast`.
            let contrasted = c * params.contrast + (0.5 - 0.5 * params.contrast)
            return contrasted * params.brightness

        case kHSVShift:
            let hsb = ColorMath.rgbToHSB(r: Double(c.x), g: Double(c.y), b: Double(c.z))
            let saturation = min(max(hsb.s * Double(params.saturation), 0), 1)
            let value = min(max(hsb.v * Double(params.value), 0), 1)
            let rgb = ColorMath.hsbToRGB(h: hsb.h + Double(params.hueTurns), s: saturation, v: value)
            return SIMD3<Float>(Float(rgb.r), Float(rgb.g), Float(rgb.b))

        case kGradientMap:
            let stop = index(luminance(c))
            let mapped = SIMD3<Float>(entry(lut, stop, 0), entry(lut, stop, 1), entry(lut, stop, 2))
            return c + (mapped - c) * params.mix

        case kPosterize:
            let steps = max(params.levels - 1, 1)
            let dither = 0.5 + params.screenStrength * (screen(params.screen, x: x, y: y) - 0.5)
            return SIMD3<Float>((c.x * steps + dither).rounded(.down) / steps,
                                (c.y * steps + dither).rounded(.down) / steps,
                                (c.z * steps + dither).rounded(.down) / steps)

        case kNoise:
            let deviation = params.isMonochrome != 0
                ? SIMD3<Float>(repeating: (noiseValue(x, y, params.seed, 0) - 0.5) * 2 * params.amount)
                : SIMD3<Float>((noiseValue(x, y, params.seed, 0) - 0.5) * 2 * params.amount,
                               (noiseValue(x, y, params.seed, 1) - 0.5) * 2 * params.amount,
                               (noiseValue(x, y, params.seed, 2) - 0.5) * 2 * params.amount)
            return c + deviation

        default:
            return c
        }
    }

    /// W3C Compositing and Blending Level 1's `Lum`, which `Compositor.swift` and `Composite.metal`
    /// both already state — see `Effect.GradientMap` for why the gradient is indexed by this and not by
    /// some other brightness.
    private static func luminance(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }

    /// The table index for one channel value. `floor(v * 255 + 0.5)` rather than any of Swift's
    /// rounding rules, because half-up is the one expression that can be written identically in both
    /// languages — Metal's `round` is half-away-from-zero and Swift's default is half-to-even, and a
    /// table lookup that disagreed by one index would step by however steep the curve is there rather
    /// than by a channel step.
    private static func index(_ value: Float) -> Int {
        Int(min(max(value, 0), 1) * 255 + 0.5)
    }

    private static func entry(_ lut: [UInt8], _ index: Int, _ channel: Int) -> Float {
        Float(lut[min(max(index, 0), 255) * 4 + channel]) / 255
    }

    /// The screen's value at one pixel, in `[0, 1)` and averaging 0.5 — see `Effect.Posterize` for why
    /// the mean matters (it is what makes `screenStrength == 0` exactly plain rounding).
    private static func screen(_ kind: UInt32, x: Int, y: Int) -> Float {
        let cell = (y & 3) * 4 + (x & 3)
        switch kind {
        case 1:  return (Float(bayer4[cell]) + 0.5) / 16
        case 2:  return (Float(clustered4[cell]) + 0.5) / 16
        default: return 0.5
        }
    }

    /// The standard 4×4 Bayer (recursive dispersed-dot) matrix.
    private static let bayer4: [Int] = [
         0,  8,  2, 10,
        12,  4, 14,  6,
         3, 11,  1,  9,
        15,  7, 13,  5,
    ]

    /// The classic 4×4 clustered-dot screen: the thresholds spiral outward from one cell, so growing
    /// coverage grows a dot rather than scattering pixels. That clustering is the whole difference
    /// between a halftone and a dither.
    private static let clustered4: [Int] = [
        12,  5,  6, 13,
         4,  0,  1,  7,
        11,  3,  2,  8,
        15, 10,  9, 14,
    ]

    /// A hash of position and seed, in `[0, 1)`.
    ///
    /// **Integer arithmetic, then a 24-bit truncation, and both halves are load-bearing.** Metal's
    /// `uint` wraps by definition and Swift's `&*`/`&+` are the same operation, so the mix below is
    /// bit-identical across the two languages where a float-based hash (`fract(sin(dot(…)) * 43758.5)`,
    /// the usual shader idiom) would depend on `sin`'s last bit and on whether fast math rewrote the
    /// multiply. Truncating to the top 24 bits before the conversion keeps the result exactly
    /// representable in `Float`, so neither side has a rounding decision to make either.
    private static func noiseValue(_ x: Int, _ y: Int, _ seed: UInt32, _ salt: UInt32) -> Float {
        var h = UInt32(truncatingIfNeeded: x) &* 374_761_393
        h = h &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
        h = h &+ seed &* 2_246_822_519 &+ salt &* 3_266_489_917
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h >> 8) / 16_777_216
    }

    // MARK: - The one gather effect

    /// Red sampled at `+offset`, blue at `-offset`, green where it is, each unpremultiplied by the
    /// alpha it was sampled with and the triple re-premultiplied by the alpha at the pixel itself.
    ///
    /// That last part is what keeps the contract: the shape of the artwork is the green channel's
    /// alpha, so the fringe appears in colour and never in coverage. Where a displaced sample lands on
    /// transparency its channel contributes nothing, which is the dark fringe real lateral aberration
    /// shows at a hard edge.
    private static func chromaticAberration(_ bytes: [UInt8], params: EffectParams,
                                            width: Int, height: Int) -> [UInt8] {
        var result = bytes
        let offset = SIMD2<Float>(params.offsetX, params.offsetY)
        for y in 0..<height {
            for x in 0..<width {
                let position = SIMD2<Float>(Float(x), Float(y))
                let centre = sample(bytes, position, width: width, height: height)
                let alpha = centre.w
                let pixel = (x + y * width) * 4
                guard alpha > 0 else {
                    for channel in 0..<4 { result[pixel + channel] = 0 }
                    continue
                }
                let shiftedRed = sample(bytes, position + offset, width: width, height: height)
                let shiftedBlue = sample(bytes, position - offset, width: width, height: height)
                let colour = clamp(SIMD3<Float>(shiftedRed.w > 0 ? shiftedRed.x / shiftedRed.w : 0,
                                                centre.y / alpha,
                                                shiftedBlue.w > 0 ? shiftedBlue.z / shiftedBlue.w : 0))
                for channel in 0..<3 { result[pixel + channel] = quantize(colour[channel] * alpha) }
                result[pixel + 3] = quantize(alpha)
            }
        }
        return result
    }

    /// Bilinear, clamp-to-edge, on premultiplied values — see `Effect.ChromaticAberration` for why the
    /// interpolation is premultiplied and not unpremultiplied.
    private static func sample(_ bytes: [UInt8], _ position: SIMD2<Float>,
                               width: Int, height: Int) -> SIMD4<Float> {
        let base = SIMD2<Float>(position.x.rounded(.down), position.y.rounded(.down))
        let fraction = position - base
        let x0 = Int(base.x), y0 = Int(base.y)
        let c00 = texel(bytes, x0, y0, width: width, height: height)
        let c10 = texel(bytes, x0 + 1, y0, width: width, height: height)
        let c01 = texel(bytes, x0, y0 + 1, width: width, height: height)
        let c11 = texel(bytes, x0 + 1, y0 + 1, width: width, height: height)
        let top = c00 + (c10 - c00) * fraction.x
        let bottom = c01 + (c11 - c01) * fraction.x
        return top + (bottom - top) * fraction.y
    }

    private static func texel(_ bytes: [UInt8], _ x: Int, _ y: Int, width: Int, height: Int) -> SIMD4<Float> {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let pixel = (cx + cy * width) * 4
        return SIMD4<Float>(Float(bytes[pixel]), Float(bytes[pixel + 1]),
                            Float(bytes[pixel + 2]), Float(bytes[pixel + 3])) / 255
    }

    // MARK: - The multi-pass kernels

    /// One separable pass: a weighted sum of `2 * taps + 1` samples along `(offsetX, offsetY)`.
    ///
    /// **Premultiplied throughout, and never unpremultiplied.** Convolution is a weighted average, and
    /// averaging premultiplied values is the only form of it that is correct across an alpha edge — the
    /// same argument `chromaticAberration` makes about its bilinear tap, applied to every tap here.
    /// Because the weights are non-negative and sum to 1, the result of a valid premultiplied input is
    /// still valid (`rgb <= a` survives a convex combination), so there is nothing to re-impose
    /// afterwards.
    ///
    /// **The step is checked once for whether it lands on the pixel grid**, which the Gaussian's two
    /// axis-aligned passes always do and a directional blur's angle generally does not. On-grid taps
    /// read one texel; off-grid taps interpolate four. The check is uniform across the buffer — it is a
    /// property of the parameters, not of the pixel — so it costs nothing and saves the common case
    /// four reads a tap.
    private static func blur1D(_ bytes: [UInt8], params: EffectParams, weights: [Float],
                               width: Int, height: Int) -> [UInt8] {
        let taps = min(Int(params.taps), weights.count - 1)
        guard taps > 0 else { return bytes }

        let step = SIMD2<Float>(params.offsetX, params.offsetY)
        let onGrid = step.x == step.x.rounded() && step.y == step.y.rounded()
        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let position = SIMD2<Float>(Float(x), Float(y))
                var sum = texel(bytes, x, y, width: width, height: height) * weights[0]
                for tap in 1...taps {
                    let delta = step * Float(tap)
                    let forward: SIMD4<Float>, backward: SIMD4<Float>
                    if onGrid {
                        let dx = Int(delta.x.rounded()), dy = Int(delta.y.rounded())
                        forward = texel(bytes, x + dx, y + dy, width: width, height: height)
                        backward = texel(bytes, x - dx, y - dy, width: width, height: height)
                    } else {
                        forward = sample(bytes, position + delta, width: width, height: height)
                        backward = sample(bytes, position - delta, width: width, height: height)
                    }
                    sum += (forward + backward) * weights[tap]
                }
                let pixel = (x + y * width) * 4
                for channel in 0..<4 { result[pixel + channel] = quantize(sum[channel]) }
            }
        }
        return result
    }

    /// Bloom's bright pass: the whole premultiplied texel scaled by how far its `Lum` sits above the
    /// threshold.
    ///
    /// Scaling the premultiplied vector — rather than the colour — is what puts the brightness into
    /// *coverage*, so the blur that follows spreads a dim pixel less than a bright one without either
    /// kernel knowing that is what it is doing. `Lum` is read from the unpremultiplied colour, because
    /// "how bright is this pixel" is a question about its colour and not about how much of it is there.
    private static func bloomThreshold(_ bytes: [UInt8], params: EffectParams,
                                       width: Int, height: Int) -> [UInt8] {
        let span = max(1 - params.threshold, 1e-4)
        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let pixel = (x + y * width) * 4
                let source = texel(bytes, x, y, width: width, height: height)
                guard source.w > 0 else {
                    for channel in 0..<4 { result[pixel + channel] = 0 }
                    continue
                }
                let colour = clamp(SIMD3<Float>(source.x, source.y, source.z) / source.w)
                let weight = min(max((luminance(colour) - params.threshold) / span, 0), 1)
                for channel in 0..<4 { result[pixel + channel] = quantize(source[channel] * weight) }
            }
        }
        return result
    }

    /// Bloom's combine: the original image plus the blurred bright pass, additively, in premultiplied
    /// space.
    ///
    /// `rgb` is re-clamped against the summed alpha afterwards. Addition can push a channel above the
    /// coverage that carries it, which is not a representable premultiplied colour and would surface
    /// much later as an unpremultiply above 1 in whatever read the texture next.
    private static func bloomCombine(_ bytes: [UInt8], original: [UInt8], params: EffectParams,
                                     width: Int, height: Int) -> [UInt8] {
        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let base = texel(original, x, y, width: width, height: height)
                let glow = texel(bytes, x, y, width: width, height: height)
                let alpha = min(max(base.w + glow.w * params.intensity, 0), 1)
                let pixel = (x + y * width) * 4
                for channel in 0..<3 {
                    let value = min(max(base[channel] + glow[channel] * params.intensity, 0), 1)
                    result[pixel + channel] = quantize(min(value, alpha))
                }
                result[pixel + 3] = quantize(alpha)
            }
        }
        return result
    }

    /// The 3×3 Sobel gradient magnitude of `Lum`, read on the **premultiplied** texel — never
    /// unpremultiplied, matching `blur1D`'s convention — so a coverage edge and a colour edge are the
    /// same kind of gradient to this kernel. Clamp-to-edge at the border, the same convention every
    /// other gather kernel in this file uses.
    ///
    /// Output is `(m, m, m, m)`: a valid premultiplied colour by construction (`rgb == a`), which is
    /// why `Effect.reshapesCoverage` names Sobel rather than treating it as a grade.
    private static func sobel(_ bytes: [UInt8], params: EffectParams, width: Int, height: Int) -> [UInt8] {
        func lum(_ x: Int, _ y: Int) -> Float {
            let t = texel(bytes, x, y, width: width, height: height)
            return 0.3 * t.x + 0.59 * t.y + 0.11 * t.z
        }
        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let tl = lum(x - 1, y - 1), tc = lum(x, y - 1), tr = lum(x + 1, y - 1)
                let ml = lum(x - 1, y),                         mr = lum(x + 1, y)
                let bl = lum(x - 1, y + 1), bc = lum(x, y + 1), br = lum(x + 1, y + 1)
                // Gx = [[-1,0,1],[-2,0,2],[-1,0,1]], Gy = [[-1,-2,-1],[0,0,0],[1,2,1]] (y downward).
                let gx = (tr - tl) + 2 * (mr - ml) + (br - bl)
                let gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr)
                let magnitude = (gx * gx + gy * gy).squareRoot()
                let m = min(max(magnitude * params.amount, 0), 1)
                let byte = quantize(m)
                let pixel = (x + y * width) * 4
                for channel in 0..<4 { result[pixel + channel] = byte }
            }
        }
        return result
    }

    /// Sharpen's combine: `original + amount · (original − blur)`, on the full premultiplied vector —
    /// **exactly `bloomCombine`'s shape**, with the blurred pass standing in for bloom's glow and
    /// `amount` for its intensity. Clamped and re-imposed the same way, for the same reason: the
    /// difference can be negative as well as positive, so the sum can overshoot `[0, 1]` in either
    /// direction — the halo — and a violation would otherwise surface much later as an unpremultiply
    /// above 1.
    private static func sharpenCombine(_ bytes: [UInt8], original: [UInt8], params: EffectParams,
                                       width: Int, height: Int) -> [UInt8] {
        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let base = texel(original, x, y, width: width, height: height)
                let blurred = texel(bytes, x, y, width: width, height: height)
                let alpha = min(max(base.w + (base.w - blurred.w) * params.amount, 0), 1)
                let pixel = (x + y * width) * 4
                for channel in 0..<3 {
                    let value = min(max(base[channel] + (base[channel] - blurred[channel]) * params.amount, 0), 1)
                    result[pixel + channel] = quantize(min(value, alpha))
                }
                result[pixel + 3] = quantize(alpha)
            }
        }
        return result
    }

    /// Outline, outside mode: a pixel already part of the shape (`alpha > threshold`) is left
    /// byte-for-byte unchanged — the containment rule. A pixel outside it becomes fully opaque
    /// `(colorR, colorG, colorB, 1)` if some in-shape pixel lies within `amount` (the resolved,
    /// fractional width, carried here rather than in `taps` so the Euclidean comparison keeps its
    /// precision) Euclidean pixels away, and is left unchanged otherwise.
    ///
    /// A direct `O((2r+1)²)` search rather than a distance transform — see `Effect.maxOutlineRadius`
    /// for why that cost is bounded separately from a blur's.
    private static func outline(_ bytes: [UInt8], params: EffectParams, width: Int, height: Int) -> [UInt8] {
        let radius = Double(params.amount)
        let radiusSquared = radius * radius
        let searchRadius = Int(radius.rounded(.up))
        let threshold = params.threshold
        let strokeColor: [UInt8] = [quantize(params.colorR), quantize(params.colorG), quantize(params.colorB)]

        var result = bytes
        for y in 0..<height {
            for x in 0..<width {
                let pixel = (x + y * width) * 4
                let alpha = Float(bytes[pixel + 3]) / 255
                guard alpha <= threshold else { continue } // in the shape already: unchanged.

                var found = false
                searchLoop: for dy in -searchRadius...searchRadius {
                    for dx in -searchRadius...searchRadius {
                        guard Double(dx * dx + dy * dy) <= radiusSquared else { continue }
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbourAlpha = Float(bytes[(nx + ny * width) * 4 + 3]) / 255
                        if neighbourAlpha > threshold { found = true; break searchLoop }
                    }
                }
                guard found else { continue } // outside the stroke's reach: unchanged.
                result[pixel] = strokeColor[0]
                result[pixel + 1] = strokeColor[1]
                result[pixel + 2] = strokeColor[2]
                result[pixel + 3] = 255
            }
        }
        return result
    }

    // MARK: - Shared arithmetic

    private static func clamp(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
    }

    /// **`.toNearestOrEven` because that is the rule Metal's float→unorm8 write uses**, the same
    /// reasoning `CoreGraphicsCompositor.drawHandRolled` records: a half-way value rounded the other
    /// way is a delta of 1 on a channel that should have been exact.
    private static func quantize(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded(.toNearestOrEven))
    }
}
