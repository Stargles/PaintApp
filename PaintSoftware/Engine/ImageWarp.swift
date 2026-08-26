import CoreGraphics
import Metal
import UIKit

// MARK: - The parameter block both backends read

/// The inverse homography a warp needs, in the exact layout `Composite.metal`'s `WarpParams` has.
///
/// **Nine floats and nothing else, and the destination's origin and scale are folded into them.** A
/// kernel that also took an origin and a scale would be a second place for the composition to be
/// wrong, and the two backends would have to agree about it twice; folded, the whole of "which
/// source texel does this destination texel come from" is one matrix, and the MSL and the Swift
/// reference are reading literally the same nine numbers.
///
/// `Float` rather than `CGFloat` for the same reason `EffectParams` is: this struct is `setBytes` on
/// one side and a `constant` reference on the other, so its layout is a contract. The Swift
/// reference deliberately takes *this* and not a `Homography`, so a measured difference between the
/// backends is the sampler and the divide, never the parameters.
struct WarpParams: Equatable {
    var m0: Float = 1, m1: Float = 0, m2: Float = 0
    var m3: Float = 0, m4: Float = 1, m5: Float = 0
    var m6: Float = 0, m7: Float = 0, m8: Float = 1

    init(_ homography: Homography) {
        m0 = Float(homography.a); m1 = Float(homography.b); m2 = Float(homography.c)
        m3 = Float(homography.d); m4 = Float(homography.e); m5 = Float(homography.f)
        m6 = Float(homography.g); m7 = Float(homography.h); m8 = Float(homography.i)
    }
}

// MARK: - The warp

/// Carrying an image through a projective map — ADD_TEXT.md §3 stage 5's bake, and the layer that
/// `Engine/Deform` deliberately does not contain.
///
/// **`Quad` and `Homography` never touch an image and this file never does geometry.** §2 records
/// that `Engine/Deform` has zero `UIImage`/`CGImage`/texture references, which is what lets the whole
/// distort solver compile standalone with `swiftc` in about five seconds. The split is that rule made
/// structural: everything here is pixels, and every matrix it uses arrives already solved.
///
/// `warp` below is **the scalar Swift reference** ADD_TEXT.md §3 stage 5 asks for by name. It is not
/// a fallback bolted on afterwards: it is what makes the agreement test possible at all, because a
/// green test needs two implementations that were written to the same written-down rule rather than
/// one implementation compared against itself (§1, "The Swift and MSL warps must be tested against
/// each other, not each against itself"). It is also the real path on a device with no Metal library,
/// the way `EffectReference` backs `applyEffect`.
enum ImageWarp {

    /// One destination pixel's worth of the rule, stated once so both readers of this file — and the
    /// MSL beside it — can be checked against the same sentence:
    ///
    /// 1. The destination pixel's **centre** is `(x + 0.5, y + 0.5)`.
    /// 2. Push it through the inverse matrix: `w = m6·x + m7·y + m8`; **discard where `w ≤ 0`**,
    ///    which is the far side of the vanishing line and has no source at all.
    /// 3. `(u, v)` is the numerator over `w`, in source **texel** coordinates — texel `i` covers
    ///    `[i, i+1)`, so its centre is at `i + 0.5`.
    /// 4. Bilinear over the four texels around `(u − 0.5, v − 0.5)`, **transparent** outside the
    ///    source rather than clamped to its edge, on premultiplied values.
    ///
    /// Transparent-outside rather than clamp-to-edge is the one place this departs from
    /// `Composite.metal`'s existing `sampleBilinear`, and it is not a preference: the source here is a
    /// glyph bitmap that a sized box has *clipped*, so its edge texels can be opaque ink. Clamping
    /// would smear that ink outwards across the whole destination as an infinite skirt. A sprite warp
    /// wants nothing outside its own rectangle.
    static func warp(source: [UInt8], sourceWidth: Int, sourceHeight: Int,
                     destinationWidth width: Int, destinationHeight height: Int,
                     params: WarpParams) -> [UInt8]? {
        guard sourceWidth > 0, sourceHeight > 0, width > 0, height > 0,
              source.count >= sourceWidth * sourceHeight * 4 else { return nil }
        var out = [UInt8](repeating: 0, count: width * height * 4)

        // Read as `Double` from the `Float` block: same numbers the kernel gets, arithmetic wide
        // enough that this side is the reference rather than a second approximation.
        let m0 = Double(params.m0), m1 = Double(params.m1), m2 = Double(params.m2)
        let m3 = Double(params.m3), m4 = Double(params.m4), m5 = Double(params.m5)
        let m6 = Double(params.m6), m7 = Double(params.m7), m8 = Double(params.m8)

        source.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                func texel(_ x: Int, _ y: Int) -> (Double, Double, Double, Double) {
                    guard x >= 0, y >= 0, x < sourceWidth, y < sourceHeight else { return (0, 0, 0, 0) }
                    let o = (y * sourceWidth + x) * 4
                    return (Double(src[o]), Double(src[o + 1]), Double(src[o + 2]), Double(src[o + 3]))
                }
                for y in 0..<height {
                    let py = Double(y) + 0.5
                    for x in 0..<width {
                        let px = Double(x) + 0.5
                        let w = m6 * px + m7 * py + m8
                        let offset = (y * width + x) * 4
                        guard w > 0 else {
                            dst[offset] = 0; dst[offset + 1] = 0; dst[offset + 2] = 0; dst[offset + 3] = 0
                            continue
                        }
                        let inv = 1 / w
                        let u = (m0 * px + m1 * py + m2) * inv - 0.5
                        let v = (m3 * px + m4 * py + m5) * inv - 0.5
                        let x0 = (u).rounded(.down), y0 = (v).rounded(.down)
                        let fx = u - x0, fy = v - y0
                        let ix = Int(x0), iy = Int(y0)
                        let t00 = texel(ix, iy), t10 = texel(ix + 1, iy)
                        let t01 = texel(ix, iy + 1), t11 = texel(ix + 1, iy + 1)
                        func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> UInt8 {
                            let top = a + (b - a) * fx
                            let bottom = c + (d - c) * fx
                            let value = top + (bottom - top) * fy
                            return UInt8(max(0, min(255, value.rounded())))
                        }
                        dst[offset] = blend(t00.0, t10.0, t01.0, t11.0)
                        dst[offset + 1] = blend(t00.1, t10.1, t01.1, t11.1)
                        dst[offset + 2] = blend(t00.2, t10.2, t01.2, t11.2)
                        dst[offset + 3] = blend(t00.3, t10.3, t01.3, t11.3)
                    }
                }
            }
        }
        return out
    }

    // MARK: - Composing the matrix

    /// The matrix step 2 above wants: **destination texel coordinates to source texel coordinates**.
    ///
    /// Read right to left, it is four maps: undo the destination's own scale, shift by where the
    /// destination sits in canvas space, invert the box-to-quad homography, then scale box points up
    /// to source texels.
    ///
    /// The result is normalised so its weight is positive over the artwork, which is what makes the
    /// kernel's `w ≤ 0` discard mean "past the vanishing line" rather than "the determinant happened
    /// to come out negative". A homography is defined up to scale, so the normalisation changes no
    /// sampled pixel.
    static func inverseTexelMap(homography: Homography, boxSize: CGSize, sourceScale: CGFloat,
                                destinationOrigin: CGPoint, destinationScale: CGFloat) -> Homography? {
        guard sourceScale > 0, destinationScale > 0, let inverse = homography.inverse else { return nil }
        let composed = Homography.scale(x: sourceScale, y: sourceScale)
            * inverse
            * Homography.translation(x: destinationOrigin.x, y: destinationOrigin.y)
            * Homography.scale(x: 1 / destinationScale, y: 1 / destinationScale)
        // The box's centre carried into destination texels: a point that is inside the artwork by
        // construction, whichever way the quad is wound.
        let boxCentre = CGPoint(x: boxSize.width / 2, y: boxSize.height / 2)
        guard let canvasCentre = homography.map(boxCentre) else { return nil }
        let reference = CGPoint(x: (canvasCentre.x - destinationOrigin.x) * destinationScale,
                                y: (canvasCentre.y - destinationOrigin.y) * destinationScale)
        return composed.normalized(forPositiveWeightAt: reference)
    }

    // MARK: - Images

    /// The whole bake in one call: a `CGImage` holding the source box, carried onto `homography`'s
    /// quad and rasterised into `destination` at one texel per canvas point.
    ///
    /// **GPU when there is one, the scalar reference when there is not**, chosen the same way
    /// `Compositor.composite` chooses between Metal and CoreGraphics — and the two are pinned against
    /// each other by `WarpAgreementCharacterizationTests`, so the choice is a performance decision
    /// rather than a correctness one.
    ///
    /// One allocation of the destination's size, once, at commit. ADD_TEXT.md §4 rule 7: the same
    /// shape and cost as a fill commit, which is already accepted. Nothing in the live path comes
    /// here — that is Core Animation, rule 2.
    static func warpedImage(source: CGImage, sourceScale: CGFloat, boxSize: CGSize,
                            homography: Homography, destination: CGRect) -> CGImage? {
        let width = Int(destination.width.rounded()), height = Int(destination.height.rounded())
        guard width > 0, height > 0, source.width > 0, source.height > 0 else { return nil }
        guard let matrix = inverseTexelMap(homography: homography, boxSize: boxSize,
                                           sourceScale: sourceScale,
                                           destinationOrigin: destination.origin,
                                           destinationScale: 1) else { return nil }
        guard let bytes = CoreGraphicsCompositor.premultipliedBytes(source, width: source.width,
                                                                    height: source.height) else { return nil }
        let params = WarpParams(matrix)
        let warped = MetalWarpEngine.shared?.warp(bytes, sourceWidth: source.width,
                                                  sourceHeight: source.height,
                                                  destinationWidth: width, destinationHeight: height,
                                                  params: params)
            ?? warp(source: bytes, sourceWidth: source.width, sourceHeight: source.height,
                    destinationWidth: width, destinationHeight: height, params: params)
        guard let warped else { return nil }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: warped, width: width, height: height)
    }
}

// MARK: - The kernel, on its own

/// Runs `warpHomography` over one buffer of the app's bytes, on the GPU.
///
/// **`MetalEffectEngine`'s shape, deliberately and to the letter**: its own device and queue, a byte
/// round-trip in the app's exact layout, and a failable singleton so a device with no Metal library
/// disables this and nothing else. That mirroring is what makes the agreement test a measurement of
/// the two *warps* — both sides take premultiplied RGBA8 in the app's layout and return the same, so
/// there is no `UIGraphicsImageRenderer`, no colour space and no second byte layout anywhere in the
/// comparison.
///
/// It is **not** the render path in the sense a frame is: this uploads and reads back per call, which
/// is exactly right for a bake that happens once at commit and would be wrong for anything per-frame.
final class MetalWarpEngine {

    static let shared = MetalWarpEngine()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let state: MTLComputePipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        // By `Bundle(for:)` and not `Bundle.main`, for the reason `CompositorMetalEngine` records:
        // under XCUITest the main bundle is the runner app, and the compiled `default.metallib` lives
        // in the `.xctest` plug-in this class is a member of. Without this line the fast tier could
        // not exercise the kernel at all, and the agreement test would silently be comparing the
        // reference against itself.
        let library = (try? device.makeDefaultLibrary(bundle: Bundle(for: MetalWarpEngine.self)))
            ?? device.makeDefaultLibrary()
        guard let library, let function = library.makeFunction(name: "warpHomography"),
              let state = try? device.makeComputePipelineState(function: function) else { return nil }
        self.device = device
        self.queue = queue
        self.state = state
    }

    /// Returns nil for a degenerate size or an allocation this device would not make — never a
    /// silently wrong answer, so `ImageWarp.warpedImage` can fall through to the scalar reference.
    func warp(_ bytes: [UInt8], sourceWidth: Int, sourceHeight: Int,
              destinationWidth: Int, destinationHeight: Int, params: WarpParams) -> [UInt8]? {
        guard sourceWidth > 0, sourceHeight > 0, destinationWidth > 0, destinationHeight > 0,
              bytes.count >= sourceWidth * sourceHeight * 4 else { return nil }
        guard let source = makeTexture(width: sourceWidth, height: sourceHeight, usage: [.shaderRead]),
              let result = makeTexture(width: destinationWidth, height: destinationHeight,
                                       usage: [.shaderWrite]),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return nil }

        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            source.replace(region: MTLRegionMake2D(0, 0, sourceWidth, sourceHeight), mipmapLevel: 0,
                           withBytes: base, bytesPerRow: sourceWidth * 4)
        }
        var params = params
        encoder.setComputePipelineState(state)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(result, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<WarpParams>.stride, index: 0)
        let tw = min(16, state.maxTotalThreadsPerThreadgroup)
        let th = min(16, max(1, state.maxTotalThreadsPerThreadgroup / tw))
        encoder.dispatchThreads(MTLSize(width: destinationWidth, height: destinationHeight, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.error == nil else { return nil }

        var output = [UInt8](repeating: 0, count: destinationWidth * destinationHeight * 4)
        output.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            result.getBytes(base, bytesPerRow: destinationWidth * 4,
                            from: MTLRegionMake2D(0, 0, destinationWidth, destinationHeight),
                            mipmapLevel: 0)
        }
        return output
    }

    /// `rgba8Unorm`, **not** `rgba8Unorm_srgb` — `Composite.metal`'s header argues that distinction,
    /// and it is as load-bearing for a resample as it is for a blend.
    private func makeTexture(width: Int, height: Int, usage: MTLTextureUsage) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = .shared // read back on the CPU without a blit
        return device.makeTexture(descriptor: descriptor)
    }
}
