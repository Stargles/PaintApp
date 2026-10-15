import CoreGraphics
import Metal
import Foundation

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

/// Raster windows keep the matrix in the whole destination's pixel grid. Folding a window's
/// origin into Float matrix coefficients would round differently from the full-frame draw.
struct RasterWarpParams {
    var map: WarpParams
    var sourceX: Int32, sourceY: Int32
    var destinationX: Int32, destinationY: Int32
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

    /// A source apron and its complete transient byte charge. Source coordinates are global
    /// texels, destination coordinates are global output texels; the matrix includes output scale
    /// but never the output window's origin. Source pixels outside the canvas are transparent.
    struct RasterPlan {
        let sourceRect: CGRect
        let destinationRect: CGRect
        let params: RasterWarpParams
        let workingBytes: Int

        init?(sourceSize: CGSize, destination: CGRect, inverseTexelMap: Homography) {
            let limit = CGFloat(Int32.max / 4)
            guard sourceSize.width > 0, sourceSize.height > 0,
                  sourceSize.width < limit, sourceSize.height < limit,
                  sourceSize.width.rounded() == sourceSize.width,
                  sourceSize.height.rounded() == sourceSize.height,
                  !destination.isEmpty, !destination.isNull, destination == destination.integral,
                  [destination.minX, destination.minY, destination.maxX, destination.maxY]
                    .allSatisfy({ $0.isFinite && abs($0) < limit }) else { return nil }
            let p = WarpParams(inverseTexelMap)
            let m = [p.m0, p.m1, p.m2, p.m3, p.m4, p.m5, p.m6, p.m7, p.m8].map(Double.init)
            guard m.allSatisfy(\.isFinite) else { return nil }
            let corners = [CGPoint(x: destination.minX + 0.5, y: destination.minY + 0.5),
                           CGPoint(x: destination.maxX - 0.5, y: destination.minY + 0.5),
                           CGPoint(x: destination.minX + 0.5, y: destination.maxY - 0.5),
                           CGPoint(x: destination.maxX - 0.5, y: destination.maxY - 0.5)]
            let weights = corners.map { m[6] * $0.x + m[7] * $0.y + m[8] }
            var needed = CGRect.null
            func include<Points: Sequence>(_ points: Points, minimumWeight: Double) -> Bool where Points.Element == CGPoint {
                var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
                var dx = 0.0, dy = 0.0, ex = 0.0, ey = 0.0
                for point in points {
                    let x = point.x, y = point.y, w = m[6] * x + m[7] * y + m[8]
                    let u = (m[0] * x + m[1] * y + m[2]) / w
                    let v = (m[3] * x + m[4] * y + m[5]) / w
                    x0 = min(x0, u); x1 = max(x1, u); y0 = min(y0, v); y1 = max(y1, v)
                    // Derivative numerators are linear; their absolute maxima are at corners.
                    dx = max(dx, abs((m[0] * m[7] - m[1] * m[6]) * y + m[0] * m[8] - m[2] * m[6]))
                    dy = max(dy, abs((m[1] * m[6] - m[0] * m[7]) * x + m[1] * m[8] - m[2] * m[7]))
                    ex = max(ex, abs((m[3] * m[7] - m[4] * m[6]) * y + m[3] * m[8] - m[5] * m[6]))
                    ey = max(ey, abs((m[4] * m[6] - m[3] * m[7]) * x + m[4] * m[8] - m[5] * m[7]))
                }
                let denominator = minimumWeight * minimumWeight
                let rx = 3 * max(1, hypot(dx, dy) / denominator)
                let ry = 3 * max(1, hypot(ex, ey) / denominator)
                func fits(_ value: Double) -> Bool { value.isFinite && abs(value) < Double(limit) }
                guard fits(x0), fits(x1), fits(y0), fits(y1), fits(rx), fits(ry) else { return false }
                // Cover Float evaluation/rounding as well as the mathematical filter support.
                let apron = 1 + 8 * Double(Float.ulpOfOne) * max(abs(x0), abs(x1), abs(y0), abs(y1), rx, ry)
                needed = needed.union(CGRect(x: x0 - 0.5 - rx - apron, y: y0 - 0.5 - ry - apron,
                                            width: x1 - x0 + 2 * (rx + apron) + 1,
                                            height: y1 - y0 + 2 * (ry + apron) + 1))
                return true
            }
            if let minimum = weights.min(), minimum > 0 {
                guard include(corners, minimumWeight: minimum) else { return nil }
            } else if weights.contains(where: { $0 > 0 }) {
                // A tile crosses the horizon. Only actual positive-weight pixel centres matter;
                // scanning this exceptional tile avoids refusing the valid part of a perspective.
                for y in Int(destination.minY)..<Int(destination.maxY) {
                    for x in Int(destination.minX)..<Int(destination.maxX) {
                        let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                        let w = m[6] * point.x + m[7] * point.y + m[8]
                        if w > 0, !include(CollectionOfOne(point), minimumWeight: w) { return nil }
                    }
                }
            }
            let clipped = needed.intersection(CGRect(origin: .zero, size: sourceSize))
            sourceRect = clipped.isNull ? .zero : clipped.integral
            destinationRect = destination
            params = RasterWarpParams(map: p, sourceX: Int32(sourceRect.minX), sourceY: Int32(sourceRect.minY),
                                      destinationX: Int32(destination.minX), destinationY: Int32(destination.minY))
            // Cropped image + normalized bytes + upload; output texture + readback + image.
            let bytes = 12 * (sourceRect.width * sourceRect.height + destination.width * destination.height)
            guard bytes.isFinite, bytes < CGFloat(Int.max / 2) else { return nil }
            workingBytes = Int(bytes)
        }
    }

    /// The same bounded sampler serves a full image and any output window. Tiles change only
    /// storage, never coordinates or filter support. The consumer must discard its new picture on
    /// false; a failed tile must not become an intentional clear or certify an edit.
    static func drawRaster(sourceSize: CGSize, destination: CGRect, inverseTexelMap: Homography,
                           maximumWorkingBytes: Int = CompositorBudget.textureBudgetBytes,
                           source: (CGRect) -> CGImage?, consume: (CGImage, CGRect) -> Void) -> Bool {
        guard !destination.isNull, !destination.isEmpty, destination == destination.integral,
              [destination.minX, destination.minY, destination.maxX, destination.maxY]
                .allSatisfy({ $0.isFinite && abs($0) < CGFloat(Int32.max / 4) }),
              maximumWorkingBytes > 0 else { return false }
        func draw(_ rect: CGRect) -> Bool {
            guard let plan = RasterPlan(sourceSize: sourceSize, destination: rect,
                                        inverseTexelMap: inverseTexelMap) else { return false }
            if plan.workingBytes > maximumWorkingBytes {
                guard max(rect.width, rect.height) > 1 else { return false }
                let vertical = rect.width >= rect.height
                let first = floor((vertical ? rect.width : rect.height) / 2)
                let a = CGRect(x: rect.minX, y: rect.minY,
                               width: vertical ? first : rect.width, height: vertical ? rect.height : first)
                let b = CGRect(x: vertical ? a.maxX : rect.minX, y: vertical ? rect.minY : a.maxY,
                               width: vertical ? rect.width - first : rect.width,
                               height: vertical ? rect.height : rect.height - first)
                return draw(a) && draw(b)
            }
            return autoreleasepool {
                guard let image = rasterImage(plan: plan, maximumWorkingBytes: maximumWorkingBytes, source: source) else { return false }
                consume(image, rect)
                return true
            }
        }
        for y in stride(from: destination.minY, to: destination.maxY, by: 512) {
            for x in stride(from: destination.minX, to: destination.maxX, by: 512) {
                if !draw(CGRect(x: x, y: y, width: min(512, destination.maxX - x),
                                height: min(512, destination.maxY - y))) { return false }
            }
        }
        return true
    }

    static func rasterImage(plan: RasterPlan, maximumWorkingBytes: Int = CompositorBudget.textureBudgetBytes,
                            source: (CGRect) -> CGImage?) -> CGImage? {
        guard plan.workingBytes <= maximumWorkingBytes,
              CompositorBudget.hasHeadroom(for: plan.workingBytes) else { return nil }
        let width = Int(plan.destinationRect.width), height = Int(plan.destinationRect.height)
        let bytes: [UInt8]
        if plan.sourceRect.isEmpty { bytes = [UInt8](repeating: 0, count: width * height * 4) }
        else {
            let sw = Int(plan.sourceRect.width), sh = Int(plan.sourceRect.height)
            guard let image = source(plan.sourceRect), image.width == sw, image.height == sh,
                  let input = CoreGraphicsCompositor.premultipliedBytes(image, width: sw, height: sh),
                  let result = MetalWarpEngine.shared?.raster(input, plan: plan) else { return nil }
            bytes = result
        }
        return CoreGraphicsCompositor.makeImage(fromPremultiplied: bytes, width: width, height: height)
    }

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
        let m0 = Double(params.m0), m1 = Double(params.m1), m2 = Double(params.m2)
        let m3 = Double(params.m3), m4 = Double(params.m4), m5 = Double(params.m5)
        let m6 = Double(params.m6), m7 = Double(params.m7), m8 = Double(params.m8)
        return warp(source: source, sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                    destinationWidth: width, destinationHeight: height) { point in
            let px = Double(point.x), py = Double(point.y)
            let w = m6 * px + m7 * py + m8
            guard w > 0 else { return nil }
            let inv = 1 / w
            return CGPoint(x: (m0 * px + m1 * py + m2) * inv,
                           y: (m3 * px + m4 * py + m5) * inv)
        }
    }

    /// The same premultiplied bilinear sampler with an arbitrary destination-to-source map.
    /// Coordinates are texel centres; nil means transparent. Liquify supplies its composed inverse
    /// here so geometry and pixels use one field rather than separate displacement implementations.
    static func warp(source: [UInt8], sourceWidth: Int, sourceHeight: Int,
                     destinationWidth width: Int, destinationHeight height: Int,
                     inverseTexelMap: (CGPoint) -> CGPoint?) -> [UInt8]? {
        guard sourceWidth > 0, sourceHeight > 0, width > 0, height > 0,
              source.count >= sourceWidth * sourceHeight * 4 else { return nil }
        var out = [UInt8](repeating: 0, count: width * height * 4)

        source.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                func texel(_ x: Int, _ y: Int) -> PremultipliedPixel {
                    guard x >= 0, y >= 0, x < sourceWidth, y < sourceHeight else { return (0, 0, 0, 0) }
                    let o = (y * sourceWidth + x) * 4
                    return (src[o], src[o + 1], src[o + 2], src[o + 3])
                }
                for y in 0..<height {
                    let py = Double(y) + 0.5
                    for x in 0..<width {
                        let px = Double(x) + 0.5
                        let offset = (y * width + x) * 4
                        guard let mapped = inverseTexelMap(CGPoint(x: px, y: py)) else {
                            dst[offset] = 0; dst[offset + 1] = 0; dst[offset + 2] = 0; dst[offset + 3] = 0
                            continue
                        }
                        let u = Double(mapped.x) - 0.5
                        let v = Double(mapped.y) - 0.5
                        // **The one place this loop can crash rather than draw nothing.** A
                        // destination pixel a hair inside the vanishing line has `w` a hair above
                        // zero, so `u` and `v` come out at 1e17 and beyond — and `Int(_:)` on a
                        // `Double` that will not fit **traps**, taking the process with it. The GPU
                        // has no such cliff: `int(base.x)` in MSL is merely undefined-but-quiet, and
                        // every branch it feeds is a bounds test that says "outside".
                        //
                        // Refusing here is not an approximation of that: a `u` outside `(-1,
                        // sourceWidth)` puts *both* bilinear taps out of bounds, and `texel` returns
                        // transparent for both, so the blend below would have written zero anyway.
                        // The bound is stated at `-1` rather than at `0` because `u = -0.4` still
                        // reaches texel 0 with weight `fx`. NaN fails every comparison and lands
                        // here too, which is the answer it should get.
                        guard u > -1, u < Double(sourceWidth), v > -1, v < Double(sourceHeight) else {
                            dst[offset] = 0; dst[offset + 1] = 0; dst[offset + 2] = 0; dst[offset + 3] = 0
                            continue
                        }
                        let pixel = samplePremultiplied(at: mapped, texel: texel)
                        dst[offset] = pixel.0; dst[offset + 1] = pixel.1
                        dst[offset + 2] = pixel.2; dst[offset + 3] = pixel.3
                    }
                }
            }
        }
        return out
    }

    typealias PremultipliedPixel = (UInt8, UInt8, UInt8, UInt8)

    /// The tiled sampler's integer domain. A bounded image may treat unsupported points as outside;
    /// a procedural picture must check this first so unsupported transport refuses the whole draw.
    static func supportsSampling(at point: CGPoint) -> Bool {
        let u = Double(point.x) - 0.5, v = Double(point.y) - 0.5
        return u.isFinite && v.isFinite && abs(u) < Double(Int.max / 4) && abs(v) < Double(Int.max / 4)
    }

    /// Shared bilinear rule for contiguous images and bounded native-material tiles. Source texels
    /// are supplied explicitly so a long vector stroke never requires a whole-stroke bitmap.
    static func samplePremultiplied(at point: CGPoint,
                                   texel: (Int, Int) -> PremultipliedPixel) -> PremultipliedPixel {
        let u = Double(point.x) - 0.5, v = Double(point.y) - 0.5
        guard supportsSampling(at: point) else { return (0, 0, 0, 0) }
        let x0 = u.rounded(.down), y0 = v.rounded(.down)
        let fx = u - x0, fy = v - y0, ix = Int(x0), iy = Int(y0)
        let a = texel(ix, iy), b = texel(ix + 1, iy), c = texel(ix, iy + 1), d = texel(ix + 1, iy + 1)
        func blend(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt8 {
            let top = Double(a) + (Double(b) - Double(a)) * fx
            let bottom = Double(c) + (Double(d) - Double(c)) * fx
            return UInt8(max(0, min(255, (top + (bottom - top) * fy).rounded())))
        }
        return (blend(a.0, b.0, c.0, d.0), blend(a.1, b.1, c.1, d.1),
                blend(a.2, b.2, c.2, d.2), blend(a.3, b.3, c.3, d.3))
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

    /// Backing texels per destination point: **1 for every destination inside the cap, and shrinking
    /// beyond it** so the longest side lands exactly on `maximumTexels`.
    ///
    /// A pure function rather than three lines inside `warpedImage` because it is the memory bound
    /// stated as arithmetic, and a bound nothing can assert is a bound nobody has.
    static func destinationScale(for destination: CGRect, maximumTexels: CGFloat) -> CGFloat {
        let longest = max(destination.width, destination.height)
        guard longest > maximumTexels, longest > 0 else { return 1 }
        return maximumTexels / longest
    }

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
    ///
    /// **`destination` is a rectangle in canvas points; `maximumDestinationTexels` is what stops it
    /// being a memory bound the caller merely hoped for.** Three buffers are `w × h × 4` here — the
    /// destination `MTLTexture`, the byte array read back off it and the `CGImage` made from that —
    /// so an uncapped destination is twelve bytes of transient per destination *point*, on top of
    /// the canvas-sized flatten and composite the bake already pays. Past the cap the warp is
    /// rendered at `destinationScale < 1` and drawn back up into the full rectangle by the caller,
    /// which is a soft edge rather than a refusal or a jetsam. The scale is folded into the matrix
    /// by `inverseTexelMap`, which has taken it since it was written and was only ever passed 1.
    ///
    /// Clipping `destination` to something that can actually be seen is the caller's job and comes
    /// first — see `TextLayout.warpedGlyphs`, which intersects it with the canvas. This cap is what
    /// remains after that, for the on-canvas worst case.
    static func warpedImage(source: CGImage, sourceScale: CGFloat, boxSize: CGSize,
                            homography: Homography, destination: CGRect,
                            maximumDestinationTexels: CGFloat) -> CGImage? {
        guard destination.width >= 1, destination.height >= 1,
              source.width > 0, source.height > 0, maximumDestinationTexels >= 1 else { return nil }
        let destinationScale = destinationScale(for: destination,
                                                maximumTexels: maximumDestinationTexels)
        let width = max(1, Int((destination.width * destinationScale).rounded()))
        let height = max(1, Int((destination.height * destinationScale).rounded()))
        guard let matrix = inverseTexelMap(homography: homography, boxSize: boxSize,
                                           sourceScale: sourceScale,
                                           destinationOrigin: destination.origin,
                                           destinationScale: destinationScale) else { return nil }
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
/// Glyph bakes and bounded transformed-raster windows share this dispatch. Raster sampling keeps
/// no source images, textures or scene cache between calls.
final class MetalWarpEngine {

    static let shared = MetalWarpEngine()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let state: MTLComputePipelineState
    private let rasterState: MTLComputePipelineState?

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
        self.rasterState = library.makeFunction(name: "warpRasterLanczos").flatMap {
            try? device.makeComputePipelineState(function: $0)
        }
    }

    /// Returns nil for a degenerate size or an allocation this device would not make — never a
    /// silently wrong answer, so `ImageWarp.warpedImage` can fall through to the scalar reference.
    func warp(_ bytes: [UInt8], sourceWidth: Int, sourceHeight: Int,
              destinationWidth: Int, destinationHeight: Int, params: WarpParams) -> [UInt8]? {
        dispatch(bytes, sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                 destinationWidth: destinationWidth, destinationHeight: destinationHeight,
                 params: params, state: state)
    }

    func raster(_ bytes: [UInt8], plan: ImageWarp.RasterPlan) -> [UInt8]? {
        guard let rasterState else { return nil }
        return dispatch(bytes, sourceWidth: Int(plan.sourceRect.width), sourceHeight: Int(plan.sourceRect.height),
                        destinationWidth: Int(plan.destinationRect.width), destinationHeight: Int(plan.destinationRect.height),
                        params: plan.params, state: rasterState, completeSIMDGroups: true)
    }

    private func dispatch<Parameters>(_ bytes: [UInt8], sourceWidth: Int, sourceHeight: Int,
                                     destinationWidth: Int, destinationHeight: Int,
                                     params: Parameters, state: MTLComputePipelineState,
                                     completeSIMDGroups: Bool = false) -> [UInt8]? {
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
        withUnsafeBytes(of: &params) { raw in
            encoder.setBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        let tw = completeSIMDGroups ? state.threadExecutionWidth : min(16, state.maxTotalThreadsPerThreadgroup)
        let th = completeSIMDGroups ? 1 : min(16, max(1, state.maxTotalThreadsPerThreadgroup / tw))
        let dispatchedWidth = completeSIMDGroups ? ((destinationWidth + tw - 1) / tw) * tw : destinationWidth
        encoder.dispatchThreads(MTLSize(width: dispatchedWidth, height: destinationHeight, depth: 1),
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
