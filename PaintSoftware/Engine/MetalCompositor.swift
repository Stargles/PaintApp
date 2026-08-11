import UIKit
import Metal
import simd

// MARK: - The GPU backend
//
// §5.1's argument for Metal is per-pixel blend math over 4.2M pixels at 2048² (16.8M at 4000²), per
// node, per frame — which CoreGraphics cannot do at interactive rates. None of that math exists yet:
// phase 2's job is the substrate and the flag, phases 5 and 7 are the blend modes that need the GPU,
// and phase 9 the effects. What this file proves is that the seam is real — that a second backend
// can be dropped behind `Compositor.composite` and produce the same picture.
//
// **One correction to the plan's framing, recorded because it changes what this file costs.** §5.1
// says "the infrastructure already ships: MetalFillEngine owns a device, queue, and nine compute
// pipelines" and calls the compositor "a second consumer of an existing dependency". The device,
// queue and library-loading *patterns* are indeed reusable, and are reused below. But
// `MetalFillEngine` is built entirely on `MTLBuffer`: there is no `MTLTexture` anywhere else in this
// codebase and no `texture2d` parameter in `Fill.metal`. The textures, the upload cache and the
// readback path are new machinery, not a second consumer of old machinery.
//
// What genuinely does carry over is the pixel contract, and it carries over exactly: device RGB,
// premultiplied-last, 8 bits per component, row-major, top-left origin, scale 1 — shared by
// `PixelOps`, `RasterLayerTexture`, `MetalFillEngine`'s buffers and the fill's byte round-trip.

enum MetalCompositor {

    /// Composites `request` on the GPU, or returns nil if it cannot. `Compositor.composite` treats
    /// nil as "use the CPU reference", so every nil here is a slower frame rather than a missing one.
    ///
    /// Returns nil when there is no GPU or no shader library, and when the request needs a group
    /// rendered in isolation, which this backend does not do yet (see `flattenedLeaves`).
    static func composite(_ request: RenderRequest) -> CGImage? {
        guard let engine = CompositorMetalEngine.shared,
              let leaves = flattenedLeaves(request) else { return nil }
        return engine.composite(leaves: leaves, request: request)
    }

    /// One leaf's contribution, in evaluation order.
    struct Leaf {
        let source: LayerRenderSource
        let opacity: Double
    }

    /// The tree flattened to the sequence of leaves to draw, or **nil if any group needs its own
    /// buffer** — which today means a folder carrying an opacity other than 1, and in phase 4 will
    /// also mean a blend mode, a mask, or isolation.
    ///
    /// Bailing out is deliberate rather than lazy. Every group in a document today is a transparent
    /// parenthesis (`RenderTree.swift` hardcodes folder opacity to 1), so the flattened sequence *is*
    /// the composite for every document that exists, and the CPU reference already handles the case
    /// this one declines. Phase 4 is where isolation becomes real for both backends at once; guessing
    /// at it now would mean writing a scratch-texture path with nothing able to exercise it.
    ///
    /// Mirrors `CoreGraphicsCompositor.draw`'s rules exactly, including that a group's own
    /// `isVisible` does not gate its subtree — see the comment there for why that is today's
    /// behaviour and not an oversight.
    private static func flattenedLeaves(_ request: RenderRequest) -> [Leaf]? {
        var leaves: [Leaf] = []

        func walk(_ nodes: [RenderNode]) -> Bool {
            for node in nodes {
                switch node.content {
                case .leaf(let layerIndex):
                    guard node.isVisible,
                          request.sources.indices.contains(layerIndex),
                          let source = request.sources[layerIndex] else { continue }
                    leaves.append(Leaf(source: source, opacity: node.opacity))
                case .node(_, let inputs):
                    guard node.opacity >= 1 else { return false }
                    for input in inputs {
                        guard walk(input) else { return false }
                    }
                }
            }
            return true
        }

        return walk(request.tree) ? leaves : nil
    }
}

// MARK: - Device, pipelines, and the upload cache

/// Owns the compositor's `MTLDevice`, queue and kernels — the same shape as `MetalFillEngine`, and
/// separate from it because the two share no pipelines and a failure in one should not disable the
/// other.
final class CompositorMetalEngine {

    /// Nil when there is no GPU, no shader library, or a kernel that would not build — exactly
    /// `MetalFillEngine`'s failable-singleton contract, and for the same reason: the caller has a
    /// working path without it, so there is nothing to assert about.
    static let shared = CompositorMetalEngine()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let psOver: MTLComputePipelineState
    private let psFill: MTLComputePipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }

        // **`makeDefaultLibrary()` reads `Bundle.main`, and in a test process that is the wrong
        // bundle.** The XCUITest runner is the main bundle; this code and its compiled
        // `default.metallib` live in `PaintSoftwareUITests.xctest`, a plug-in inside it. Asking for
        // the library by the bundle that owns *this class* resolves to the app bundle in the app and
        // to the .xctest bundle under test, so one line covers both.
        //
        // This is the whole reason the GPU has never been exercisable in the fast tier, and it is
        // worth knowing that it was two problems rather than one: `Fill.metal` was never a member of
        // the test target (still isn't, so `MetalFillEngine.shared` is still nil here), *and*
        // `MetalFillEngine` asks for its library the way that cannot work from a plug-in.
        let library = (try? device.makeDefaultLibrary(bundle: Bundle(for: CompositorMetalEngine.self)))
            ?? device.makeDefaultLibrary()
        guard let library else { return nil }

        func pipeline(_ name: String) -> MTLComputePipelineState? {
            guard let fn = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }
        guard let over = pipeline("compositeOver"), let fill = pipeline("compositeFill") else { return nil }
        self.device = device
        self.queue = queue
        self.psOver = over
        self.psFill = fill
    }

    func composite(leaves: [MetalCompositor.Leaf], request: RenderRequest) -> CGImage? {
        let width = Int(request.canvasSize.width.rounded())
        let height = Int(request.canvasSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        // Ping-pong rather than one read_write accumulator: `access::read_write` on `rgba8Unorm`
        // needs the GPU family's read-write texture support, and two scratch textures cost 33.6 MB at
        // 2048² against a correctness risk on older hardware. §5.3's texture pool is what makes this
        // cheap across frames; phase 2 allocates per composite and leaves the pool to the sandwich.
        guard var front = makeScratchTexture(width: width, height: height),
              var back = makeScratchTexture(width: width, height: height),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return nil }

        // Premultiplied, so the background's own alpha scales its colour — and a nil background is a
        // transparent clear rather than a skipped step, since a scratch texture arrives undefined.
        var background = SIMD4<Float>(repeating: 0)
        if let colour = request.background?.color {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            background = SIMD4<Float>(Float(r * a), Float(g * a), Float(b * a), Float(a))
        }
        encoder.setComputePipelineState(psFill)
        encoder.setTexture(front, index: 0)
        encoder.setBytes(&background, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        dispatch2D(encoder, psFill, width: width, height: height)

        for leaf in leaves {
            guard let texture = Self.upload(leaf.source.image, device: device) else {
                encoder.endEncoding()
                return nil
            }
            var opacity = Float(leaf.opacity)
            encoder.setComputePipelineState(psOver)
            encoder.setTexture(front, index: 0)
            encoder.setTexture(texture, index: 1)
            encoder.setTexture(back, index: 2)
            encoder.setBytes(&opacity, length: MemoryLayout<Float>.stride, index: 0)
            dispatch2D(encoder, psOver, width: width, height: height)
            swap(&front, &back)
        }

        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.error == nil else { return nil }
        return readBack(front, width: width, height: height)
    }

    private func dispatch2D(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                            width: Int, height: Int) {
        let tw = min(16, pipeline.maxTotalThreadsPerThreadgroup)
        let th = min(16, max(1, pipeline.maxTotalThreadsPerThreadgroup / tw))
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    private func makeScratchTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared // read back on the CPU without a blit
        return device.makeTexture(descriptor: descriptor)
    }

    /// Reads the finished texture back as a `CGImage` in the app's standard format.
    ///
    /// The same round-trip `CanvasManager+Fill.imageFromRGBA` does for the flood fill's output, and
    /// deliberately the same constants — a byte-identical gate is decided as much by this conversion
    /// as by the arithmetic above it.
    private func readBack(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Uploads one leaf's pixels to a texture. **No cache**, deliberately — see the note in
    /// `LayerRenderSource`: the request hands out a freshly rendered `CGImage` per leaf per frame, so
    /// there is no stable identity to key on and the cache this replaced was measured never hitting.
    ///
    /// That makes the upload the dominant cost of a GPU composite (six canvas-sized layers is ~100 MB
    /// moved per frame), which is exactly why §5.2's sandwich caches the composites above and below
    /// the active layer rather than the leaves: the sandwich uploads nothing while a stroke is in
    /// progress, where a per-leaf cache would still be re-uploading whatever the user just drew on.
    ///
    /// Draws through a context of exactly the app's byte layout rather than trusting whatever backing
    /// store the `CGImage` happens to have, which for something out of `UIGraphicsImageRenderer` may
    /// be a different order or alignment.
    private static func upload(_ image: CGImage, device: MTLDevice) -> MTLTexture? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }
}
