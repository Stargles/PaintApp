import UIKit
import Metal

// MARK: - Tier 3 effects on the GPU
//
// LAYER_COMPOSITING.md §4.4/§7. The `applyEffect` half of `Composite.metal`.
//
// **The prediction this file was written on held exactly, which is worth recording.** Phase 9's
// kernels shipped before either §4.4 wrapper existed, and `EffectPipelines` was made constructible
// from any device and library rather than registered inside `CompositorMetalEngine` — so that when a
// wrapper landed the compositor would own one as a stored property and call `encode` inside the
// encoder it already had, "one line in its initialiser and one in its walk, against a type that is
// already tested". Phase 9a is that wrapper and that is what it cost.
//
// `MetalEffectEngine` below is the standalone harness that makes that possible: its own device, queue
// and byte round-trip, so the kernel is exercisable — and measurable against `EffectReference` — with
// no compositor involved at all. It is **not** the render path and must not become one; a real frame
// uploads once and keeps the texture, where this uploads and reads back per call.

/// The compositor-side handle: one pipeline, the scratch textures a multi-pass effect ping-pongs
/// through, and the encoding of one effect into an existing encoder.
///
/// Separate from the engine below because this is the part a wrapper needs. It holds no queue and no
/// canvas textures, so whoever owns the walk owns those.
///
/// **It does hold a device and up to two intermediates, and that is the one thing that changed when
/// multi-pass arrived.** §5.3 is explicit that a canvas texture is 16.8 MB at 2048² and 64 MB at 4000²
/// and that the answer is a pool reused across frames rather than an allocation per use — so the
/// intermediates live here, at the lifetime of whatever owns the pipeline, and are reallocated only
/// when the canvas size changes. Allocating them inside `encode` would put a 64 MB `makeTexture` on the
/// path of every blurred frame, which is the shape of the number phase 4 measured at 1071 ms.
///
/// Not thread-safe, deliberately: the scratch is mutable state and an encoder is a single-threaded
/// object, so the owner that serializes one serializes the other for free.
final class EffectPipelines {

    private let device: MTLDevice
    private let state: MTLComputePipelineState

    /// **At most two, whatever the pass count.** Pass *n* reads pass *n−1*'s output, the first pass
    /// reads the caller's `source` and the last writes the caller's `result`, so the intermediate
    /// outputs alternate between exactly two textures however long the list is — four passes need the
    /// same two as three.
    private var scratch: [MTLTexture] = []
    private var scratchSize = (width: 0, height: 0)

    /// Nil when the library has no `applyEffect` — the same failable contract `CompositorMetalEngine`
    /// uses, and for the same reason: the caller has `EffectReference` to fall back on.
    init?(device: MTLDevice, library: MTLLibrary) {
        guard let function = library.makeFunction(name: "applyEffect"),
              let state = try? device.makeComputePipelineState(function: function) else { return nil }
        self.device = device
        self.state = state
    }

    /// One effect, `source` graded into `result` — **one dispatch or four, and the caller cannot tell
    /// which.** That is the point of the signature not having changed: a §4.4 wrapper asks for an
    /// effect and gets however many passes that effect declares.
    ///
    /// **The bindings are exactly the values `EffectReference` reads** — kind, parameter block, table,
    /// weights — which is what "one value reaches both backends" means concretely. Nothing here looks
    /// inside the `Effect`; it reads `passes` and runs them.
    ///
    /// `source` and `result` must be different textures: the kernel reads a neighbourhood, so writing
    /// into the texture being read would sample pixels that had already been graded. `source` is also
    /// bound as `original` for the whole effect, which is what bloom's combine pass reads — so it must
    /// stay readable for the duration and is never written.
    ///
    /// **The encoder must be serial-dispatch**, which `makeComputeCommandEncoder()` gives by default:
    /// consecutive dispatches then observe each other's writes without an explicit barrier. A
    /// concurrent-dispatch encoder would need `memoryBarrier(scope: .textures)` between passes, and
    /// nothing in this project makes one.
    ///
    /// Returns false when it declined — an intermediate this device would not allocate — so the caller
    /// can fall back to `EffectReference` the way `Compositor.composite` falls back to
    /// `CoreGraphicsCompositor`, rather than being handed a half-run effect.
    @discardableResult
    func encode(_ effect: Effect, source: MTLTexture, into result: MTLTexture,
                encoder: MTLComputeCommandEncoder) -> Bool {
        let passes = effect.passes
        guard let last = passes.indices.last else { return false }
        guard intermediates(passes.count - 1, width: source.width, height: source.height) else { return false }

        let lut = effect.lookupTable
        let weights = effect.weights

        // Constant for the whole effect, so bound once: bindings persist across dispatches within an
        // encoder, and only the two that vary per pass are re-set inside the loop.
        encoder.setComputePipelineState(state)
        encoder.setTexture(source, index: 2)
        lut.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            encoder.setBytes(base, length: raw.count, index: 2)
        }
        weights.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            encoder.setBytes(base, length: raw.count, index: 3)
        }

        let tw = min(16, state.maxTotalThreadsPerThreadgroup)
        let th = min(16, max(1, state.maxTotalThreadsPerThreadgroup / tw))

        for (index, pass) in passes.enumerated() {
            // Parity of the index picks the scratch slot, which is what keeps two textures enough:
            // an output can never be its own input because consecutive indices differ in parity.
            let input = index == 0 ? source : scratch[(index - 1) % 2]
            let output = index == last ? result : scratch[index % 2]
            var kind = pass.kind
            var params = pass.params
            encoder.setTexture(input, index: 0)
            encoder.setTexture(output, index: 1)
            encoder.setBytes(&kind, length: MemoryLayout<UInt32>.stride, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<EffectParams>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: source.width, height: source.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        }
        return true
    }

    /// Gives the intermediates back.
    ///
    /// **The memory-warning valve could not reach these until this existed, and that was a hole in
    /// it.** `CompositorMetalEngine.purge` drops its pool and its upload cache and called itself
    /// correctness-neutral — which it is — but the two textures below are the same kind of pure
    /// memoization and were not in it, so a purge on a 4096² canvas gave back the pool's 192 MiB and
    /// went on holding 128 MiB of intermediates for an effect nobody was looking at. The next
    /// `encode` reallocates them, exactly as it does after a canvas resize.
    func releaseIntermediates() {
        scratch.removeAll(keepingCapacity: true)
        scratchSize = (0, 0)
    }

    /// Makes sure `count` intermediates exist at this size, allocating only what is missing.
    ///
    /// **A single-pass effect asks for zero and this returns immediately** — no allocation, no
    /// bookkeeping, nothing held. That is how the eight per-pixel effects go on costing exactly what
    /// they cost before multi-pass existed.
    ///
    /// A size change discards the pool rather than keeping both sizes: a canvas has one size at a time,
    /// and holding a stale 64 MB pair against the chance the artist resizes back is the memory §5.3
    /// says not to spend.
    private func intermediates(_ count: Int, width: Int, height: Int) -> Bool {
        guard count > 0 else { return true }
        if scratchSize != (width, height) {
            scratch.removeAll(keepingCapacity: true)
            scratchSize = (width, height)
        }
        while scratch.count < min(count, 2) {
            // `.private`: an intermediate is written and read by the GPU and never by the CPU, so it
            // has no business in shared storage the way the engine's own byte round-trip does.
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { return false }
            scratch.append(texture)
        }
        return true
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
        guard pipelines.encode(effect, source: source, into: result, encoder: encoder) else {
            encoder.endEncoding()
            return nil
        }
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
