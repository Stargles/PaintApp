import UIKit
import Metal

// MARK: - Tier 3 effects on the GPU
//
// LAYER_COMPOSITING.md §4.4/§7. The `applyEffect` half of `Composite.metal`, and **deliberately not a
// change to `MetalCompositor.swift`.**
//
// §4.4's two wrappers are what put an effect into the tree, and neither exists yet. Registering the
// effect pipeline inside `CompositorMetalEngine` before there is a walk that dispatches it would be an
// edit to the file phase 8 is currently rewriting, in exchange for nothing. `EffectPipelines` is
// instead constructible from any device and library, so when a wrapper lands the compositor owns one
// as a stored property and calls `encode` inside the encoder it already has — one line in its
// initialiser and one in its walk, against a type that is already tested.
//
// `MetalEffectEngine` below is the standalone harness that makes that possible: its own device, queue
// and byte round-trip, so the kernel is exercisable — and measurable against `EffectReference` — with
// no compositor involved at all. It is **not** the render path and must not become one; a real frame
// uploads once and keeps the texture, where this uploads and reads back per call.

/// The compositor-side handle: one pipeline, and the encoding of one effect into an existing encoder.
///
/// Separate from the engine below because this is the part a wrapper needs. It holds no device, no
/// queue and no textures, so whoever owns the walk owns those and this stays a description of how an
/// `Effect` becomes a dispatch.
final class EffectPipelines {

    private let state: MTLComputePipelineState

    /// Nil when the library has no `applyEffect` — the same failable contract `CompositorMetalEngine`
    /// uses, and for the same reason: the caller has `EffectReference` to fall back on.
    init?(device: MTLDevice, library: MTLLibrary) {
        guard let function = library.makeFunction(name: "applyEffect"),
              let state = try? device.makeComputePipelineState(function: function) else { return nil }
        self.state = state
    }

    /// One `applyEffect` dispatch: `source` graded into `result`.
    ///
    /// **The three bindings are exactly the three values `EffectReference` reads** — kind, parameter
    /// block, table — which is what "one value reaches both backends" means concretely. Nothing here
    /// looks inside the `Effect`.
    ///
    /// `source` and `result` must be different textures: the kernel reads a neighbourhood for
    /// chromatic aberration, so writing into the texture being read would sample pixels that had
    /// already been graded.
    func encode(_ effect: Effect, source: MTLTexture, into result: MTLTexture,
                encoder: MTLComputeCommandEncoder) {
        var kind = effect.kindCode
        var params = effect.params
        let lut = effect.lookupTable

        encoder.setComputePipelineState(state)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(result, index: 1)
        encoder.setBytes(&kind, length: MemoryLayout<UInt32>.stride, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<EffectParams>.stride, index: 1)
        lut.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            encoder.setBytes(base, length: raw.count, index: 2)
        }

        let width = source.width, height = source.height
        let tw = min(16, state.maxTotalThreadsPerThreadgroup)
        let th = min(16, max(1, state.maxTotalThreadsPerThreadgroup / tw))
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }
}

/// Runs one effect over one buffer of the app's bytes, on the GPU.
///
/// **The signature mirrors `EffectReference.apply` exactly, and that is the point of it.** Both take
/// premultiplied RGBA8 in the app's layout and return the same; neither converts through a `CGImage`.
/// So a measured difference between the two is the kernel against the Swift transform and nothing
/// else — no `UIGraphicsImageRenderer`, no colour space, no second byte layout to be wrong about.
final class MetalEffectEngine {

    /// Nil when there is no GPU, no shader library, or a kernel that would not build. Same failable
    /// singleton as `CompositorMetalEngine`, and a separate one for the same reason it is separate
    /// from `MetalFillEngine`: a failure in one should not disable the other.
    static let shared = MetalEffectEngine()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelines: EffectPipelines

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        // By `Bundle(for:)` and not `Bundle.main`, for the reason `CompositorMetalEngine` records:
        // under XCUITest the main bundle is the runner app, and the compiled `default.metallib` lives
        // in the `.xctest` plug-in that this class is a member of.
        let library = (try? device.makeDefaultLibrary(bundle: Bundle(for: MetalEffectEngine.self)))
            ?? device.makeDefaultLibrary()
        guard let library, let pipelines = EffectPipelines(device: device, library: library) else { return nil }
        self.device = device
        self.queue = queue
        self.pipelines = pipelines
    }

    /// Returns nil for a degenerate size or an allocation this device would not make — never a
    /// silently wrong answer, so a caller can fall back to `EffectReference` the way
    /// `Compositor.composite` falls back to `CoreGraphicsCompositor`.
    func apply(_ effect: Effect, to bytes: [UInt8], width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        guard let source = makeTexture(width: width, height: height, usage: [.shaderRead]),
              let result = makeTexture(width: width, height: height, usage: [.shaderWrite]),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return nil }

        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                           withBytes: base, bytesPerRow: width * 4)
        }
        pipelines.encode(effect, source: source, into: result, encoder: encoder)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.error == nil else { return nil }

        var output = [UInt8](repeating: 0, count: width * height * 4)
        output.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            result.getBytes(base, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return output
    }

    /// `rgba8Unorm`, **not** `rgba8Unorm_srgb` — `Composite.metal`'s header is where that distinction
    /// is argued, and it is as load-bearing for a grade as it is for a blend.
    private func makeTexture(width: Int, height: Int, usage: MTLTextureUsage) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = .shared // read back on the CPU without a blit
        return device.makeTexture(descriptor: descriptor)
    }
}
