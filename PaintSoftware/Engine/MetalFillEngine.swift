import Metal
import UIKit
import simd

/// GPU flood-fill engine (see Fill.metal). One `MetalFillEngine` owns the device + compiled kernels;
/// each fill gesture makes a `MetalFillSession` that holds the per-canvas buffers and the composited
/// reference the fill reads its walls from. A fill runs entirely on the GPU — colour-distance wall
/// detection, a jump-flooding disk close for gap bridging, a parallel scanline flood, a disk edge
/// dilate, and the final paint — so it stays real-time regardless of build configuration.
///
/// Coordinate convention matches the rest of the app: index 0 is the top-left pixel, y increases
/// downward, 1 unit = 1 pixel. Buffers are laid out as row-major `y * width + x`.
final class MetalFillEngine {
    static let shared = MetalFillEngine()

    let device: MTLDevice
    private let queue: MTLCommandQueue

    private let psWalls: MTLComputePipelineState
    private let psJfaInit: MTLComputePipelineState
    private let psJfaStep: MTLComputePipelineState
    private let psThreshold: MTLComputePipelineState
    private let psFloodInit: MTLComputePipelineState
    private let psFloodHoriz: MTLComputePipelineState
    private let psFloodVert: MTLComputePipelineState
    private let psEdgeDilate: MTLComputePipelineState
    private let psPaint: MTLComputePipelineState
    private let psEdgeBridge: MTLComputePipelineState
    private let psUnionMask: MTLComputePipelineState
    private let psFloodInitFromLasso: MTLComputePipelineState

    /// Mirror of the Metal `FillParams` struct (must match its field order/alignment exactly).
    struct FillParams {
        var width: UInt32 = 0
        var height: UInt32 = 0
        var seedX: UInt32 = 0
        var seedY: UInt32 = 0
        var threshold: Float = 0
        var gapRadius: Float = 0
        var edgeOverlap: Float = 0
        /// px the artwork rect is inset from the buffer on all four sides (see Fill.metal). Occupies
        /// the slot that used to be `_pad0`, so the layout is unchanged.
        var edgeInset: Float = 0
        var seedColor: SIMD4<Float> = .zero
        var fillColor: SIMD4<Float> = .zero
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        // By `Bundle(for:)` and not `Bundle.main`, for the reason `CompositorMetalEngine` records at
        // length: under XCUITest the main bundle is the *runner app*, while this class and its
        // compiled `default.metallib` live in the `.xctest` plug-in. Asking by the bundle that owns
        // this class resolves to the app bundle in the app and to the test bundle in the fast tier.
        //
        // That was half of why the fill's GPU path had never been exercisable headlessly; the other
        // half was that `Fill.metal` was not a member of the test target's Sources phase. Both are
        // now fixed, which is what `FillBoundaryLogicTests` runs on.
        let library = (try? device.makeDefaultLibrary(bundle: Bundle(for: MetalFillEngine.self)))
            ?? device.makeDefaultLibrary()
        guard let library else { return nil }
        func pipeline(_ name: String) -> MTLComputePipelineState? {
            guard let fn = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }
        guard let walls = pipeline("computeWalls"),
              let jfaInit = pipeline("jfaInit"),
              let jfaStep = pipeline("jfaStep"),
              let threshold = pipeline("thresholdDistance"),
              let floodInit = pipeline("floodInit"),
              let floodHoriz = pipeline("floodHoriz"),
              let floodVert = pipeline("floodVert"),
              let edgeDilate = pipeline("edgeDilate"),
              let paint = pipeline("paintRegion"),
              let edgeBridge = pipeline("edgeBridge"),
              let unionMask = pipeline("unionMask"),
              let floodInitFromLasso = pipeline("floodInitFromLasso") else { return nil }
        self.device = device
        self.queue = queue
        self.psWalls = walls
        self.psJfaInit = jfaInit
        self.psJfaStep = jfaStep
        self.psThreshold = threshold
        self.psFloodInit = floodInit
        self.psFloodHoriz = floodHoriz
        self.psFloodVert = floodVert
        self.psEdgeDilate = edgeDilate
        self.psPaint = paint
        self.psEdgeBridge = edgeBridge
        self.psUnionMask = unionMask
        self.psFloodInitFromLasso = floodInitFromLasso
    }

    /// Uploads `referenceRGBA` (premultiplied-last, row-major, `width*height*4` bytes) into a session
    /// whose buffers are reused across every fill of the same gesture. Returns nil if allocation fails.
    ///
    /// - Parameter lassoMask: one byte per pixel, non-zero inside the loop the artist drew, for the
    ///   lasso fill type. Its presence is what switches the session from a one-pixel seed to a
    ///   whole-region one; `nil` is the ordinary bucket fill. Built by `LassoFillMask.rasterize`.
    func makeSession(referenceRGBA: [UInt8], width: Int, height: Int,
                     lassoMask: [UInt8]? = nil) -> MetalFillSession? {
        MetalFillSession(engine: self, referenceRGBA: referenceRGBA, width: width, height: height,
                         lassoMask: lassoMask)
    }

    // MARK: - Encoding helpers (used by MetalFillSession)

    /// Dispatches a 2-D kernel over `width*height` threads, assuming the encoder's pipeline, buffers,
    /// and any `setBytes` have already been configured by the caller.
    fileprivate func dispatch2D(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                                width: Int, height: Int) {
        let tw = min(16, pipeline.maxTotalThreadsPerThreadgroup)
        let th = min(16, max(1, pipeline.maxTotalThreadsPerThreadgroup / tw))
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    /// Convenience for kernels that only need buffer arguments (no `setBytes`).
    fileprivate func encode2D(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                              width: Int, height: Int, buffers: [(MTLBuffer, Int)]) {
        encoder.setComputePipelineState(pipeline)
        for (buf, index) in buffers { encoder.setBuffer(buf, offset: 0, index: index) }
        dispatch2D(encoder, pipeline, width: width, height: height)
    }

    fileprivate func encode1D(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                              count: Int, buffers: [(MTLBuffer, Int)]) {
        encoder.setComputePipelineState(pipeline)
        for (buf, index) in buffers { encoder.setBuffer(buf, offset: 0, index: index) }
        let tg = MTLSize(width: min(64, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: tg)
    }

    fileprivate func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    /// Encodes `edgeBridge`, which needs a scalar radius alongside its two buffers.
    fileprivate func encodeBridge(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                                  width: Int, height: Int, coord: MTLBuffer, out: MTLBuffer,
                                  params: MTLBuffer, radius: Float) {
        var r = radius
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(coord, offset: 0, index: 0)
        encoder.setBuffer(out, offset: 0, index: 1)
        encoder.setBuffer(params, offset: 0, index: 2)
        encoder.setBytes(&r, length: MemoryLayout<Float>.size, index: 3)
        dispatch2D(encoder, pipeline, width: width, height: height)
    }

    fileprivate var pipelines: (walls: MTLComputePipelineState, jfaInit: MTLComputePipelineState,
                                jfaStep: MTLComputePipelineState, threshold: MTLComputePipelineState,
                                floodInit: MTLComputePipelineState, floodHoriz: MTLComputePipelineState,
                                floodVert: MTLComputePipelineState, edgeDilate: MTLComputePipelineState,
                                paint: MTLComputePipelineState, edgeBridge: MTLComputePipelineState,
                                unionMask: MTLComputePipelineState,
                                floodInitFromLasso: MTLComputePipelineState) {
        (psWalls, psJfaInit, psJfaStep, psThreshold, psFloodInit, psFloodHoriz, psFloodVert, psEdgeDilate,
         psPaint, psEdgeBridge, psUnionMask, psFloodInitFromLasso)
    }
}

/// Per-gesture GPU buffers + the composited reference. `fill(...)` runs the whole pipeline and returns
/// the painted region as premultiplied RGBA bytes (transparent where unfilled), ready to composite
/// onto the destination layer.
final class MetalFillSession {
    private let engine: MetalFillEngine
    let width: Int
    let height: Int
    private let count: Int

    /// CPU copy of the reference, kept so the seed colour can be sampled without a GPU round-trip.
    private let referenceRGBA: [UInt8]

    private let refBuf: MTLBuffer
    private let wallBuf: MTLBuffer
    private let dilatedBuf: MTLBuffer
    private let closedBuf: MTLBuffer
    /// The canvas-edge bridge, computed while the wall distance field is still live and folded into
    /// `closedBuf` after the erode has overwritten it. See `edgeBridge` in Fill.metal.
    private let bridgeBuf: MTLBuffer
    private let regionBuf: MTLBuffer
    private let regionTmpBuf: MTLBuffer
    private let jfaA: MTLBuffer
    private let jfaB: MTLBuffer
    private let outBuf: MTLBuffer
    /// The lasso fill's seed region — one byte per pixel, non-zero inside the loop. Nil for an
    /// ordinary bucket fill, and its nil-ness is the switch between the two seeding strategies.
    private let lassoBuf: MTLBuffer?
    private let changedBuf: MTLBuffer
    private let paramsBuf: MTLBuffer

    fileprivate init?(engine: MetalFillEngine, referenceRGBA: [UInt8], width: Int, height: Int,
                      lassoMask: [UInt8]? = nil) {
        guard width > 0, height > 0, referenceRGBA.count >= width * height * 4 else { return nil }
        if let lassoMask, lassoMask.count < width * height { return nil }
        let count = width * height
        let device = engine.device
        func buffer(_ bytes: Int) -> MTLBuffer? { device.makeBuffer(length: max(bytes, 4), options: .storageModeShared) }
        guard let refBuf = referenceRGBA.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * 4, options: .storageModeShared) }),
              let wallBuf = buffer(count), let dilatedBuf = buffer(count), let closedBuf = buffer(count),
              let bridgeBuf = buffer(count),
              let regionBuf = buffer(count), let regionTmpBuf = buffer(count),
              let jfaA = buffer(count * MemoryLayout<SIMD2<Float>>.stride),
              let jfaB = buffer(count * MemoryLayout<SIMD2<Float>>.stride),
              let outBuf = buffer(count * 4), let changedBuf = buffer(MemoryLayout<UInt32>.stride),
              let paramsBuf = buffer(MemoryLayout<MetalFillEngine.FillParams>.stride) else { return nil }
        self.engine = engine
        self.width = width
        self.height = height
        self.count = count
        if let lassoMask {
            guard let buf = lassoMask.withUnsafeBytes({
                device.makeBuffer(bytes: $0.baseAddress!, length: count, options: .storageModeShared)
            }) else { return nil }
            self.lassoBuf = buf
        } else {
            self.lassoBuf = nil
        }
        self.referenceRGBA = referenceRGBA
        self.refBuf = refBuf
        self.wallBuf = wallBuf
        self.dilatedBuf = dilatedBuf
        self.closedBuf = closedBuf
        self.bridgeBuf = bridgeBuf
        self.regionBuf = regionBuf
        self.regionTmpBuf = regionTmpBuf
        self.jfaA = jfaA
        self.jfaB = jfaB
        self.outBuf = outBuf
        self.changedBuf = changedBuf
        self.paramsBuf = paramsBuf
    }

    /// The straight-RGBA colour at `(x, y)` in the reference (0..1), used as the flood seed colour.
    func seedColor(atX x: Int, y: Int) -> SIMD4<Float> {
        guard x >= 0, x < width, y >= 0, y < height else { return .zero }
        let o = (y * width + x) * 4
        return SIMD4<Float>(Float(referenceRGBA[o]), Float(referenceRGBA[o + 1]),
                            Float(referenceRGBA[o + 2]), Float(referenceRGBA[o + 3])) / 255.0
    }

    /// Whether the reference pixel at the seed is opaque enough / distinct — currently always fills;
    /// kept as a hook mirroring the old engine's "tapped on ink" guard.
    func isSeedInBounds(x: Int, y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    /// Runs the full GPU pipeline and returns the painted region as premultiplied RGBA (row-major,
    /// `width*height*4`), transparent where unfilled. `fillColor` is premultiplied 0..1.
    ///
    /// - Parameter canvasEdgeIsWall: make the canvas edge bound the fill. Two mechanisms, both
    ///   described at length above `edgeBridge` in Fill.metal: the artwork rect's boundary becomes a
    ///   **barrier** the flood cannot travel across (unconditional — it does not consult
    ///   `gapRadius`), and gap-closing may additionally **bridge** to that edge so a stroke stopping
    ///   a few px short of it still seals.
    /// - Parameter edgeInset: px the artwork rect is inset from this buffer on all four sides, i.e.
    ///   `CanvasManager.canvasPadding`. 0 — the default, and what every caller with no padding
    ///   passes — makes the artwork rect the buffer itself, at which point both mechanisms reduce to
    ///   the buffer-rim behaviour the engine had before padding was a consideration. Ignored
    ///   entirely when `canvasEdgeIsWall` is false.
    func fill(seedX: Int, seedY: Int, seedColor: SIMD4<Float>, threshold: Float,
              gapRadius: Float, edgeOverlap: Float, canvasEdgeIsWall: Bool = false,
              edgeInset: Float = 0, fillColor: SIMD4<Float>) -> [UInt8]? {
        // A lasso session seeds from its whole mask, so there is no tapped pixel to be in bounds.
        guard lassoBuf != nil || isSeedInBounds(x: seedX, y: seedY) else { return nil }
        let p = engine.pipelines

        var params = MetalFillEngine.FillParams()
        params.width = UInt32(width); params.height = UInt32(height)
        params.seedX = UInt32(seedX); params.seedY = UInt32(seedY)
        params.threshold = threshold; params.gapRadius = gapRadius; params.edgeOverlap = edgeOverlap
        params.seedColor = seedColor; params.fillColor = fillColor
        // **One place decides what the option means**, so "off" is provably the pre-padding binary:
        // with `canvasEdgeIsWall` false the shader sees inset 0 and every edge rule collapses to the
        // buffer rim. A degenerate inset (negative, or wide enough to leave no artwork rect at all —
        // a project could load a padding inconsistent with its canvasSize) is treated the same way,
        // because a zero-area rect would fence the flood into nothing.
        let inset = edgeInset.rounded()
        params.edgeInset = (canvasEdgeIsWall && inset > 0 && 2 * inset < Float(min(width, height))) ? inset : 0
        memcpy(paramsBuf.contents(), &params, MemoryLayout<MetalFillEngine.FillParams>.size)

        // Stage 1: walls, gap-closing disk close, flood init.
        guard let cb1 = engine.makeCommandBuffer(), let enc1 = cb1.makeComputeCommandEncoder() else { return nil }
        engine.encode2D(enc1, p.walls, width: width, height: height, buffers: [(refBuf, 0), (wallBuf, 1), (paramsBuf, 2)])

        let gap = Int(gapRadius.rounded())
        let closedSource: MTLBuffer
        if gap >= 1 {
            // Dilate: distance to nearest wall <= r.
            let distWall = encodeJFA(enc1, mask: wallBuf, seedValue: 1)
            encodeThreshold(enc1, from: distWall, out: dilatedBuf, radius: gapRadius, keepInside: 1)
            // The canvas-edge bridge is computed *here*, while `distWall` is still the wall distance
            // field — the erode's own JFA below reuses the same two ping-pong buffers and destroys
            // it. Folded into the closed mask afterwards rather than into `dilatedBuf`, because
            // anything put in there is about to be eroded straight back off.
            if canvasEdgeIsWall {
                engine.encodeBridge(enc1, p.edgeBridge, width: width, height: height,
                                    coord: distWall, out: bridgeBuf, params: paramsBuf, radius: gapRadius)
            }
            // Erode the dilated mask: distance to nearest background (dilated == 0) > r.
            let distBg = encodeJFA(enc1, mask: dilatedBuf, seedValue: 0)
            encodeThreshold(enc1, from: distBg, out: closedBuf, radius: gapRadius, keepInside: 0)
            if canvasEdgeIsWall {
                engine.encode2D(enc1, p.unionMask, width: width, height: height,
                                buffers: [(bridgeBuf, 0), (closedBuf, 1), (paramsBuf, 2)])
            }
            closedSource = closedBuf
        } else {
            // No *bridge* at a zero radius — the artist has said "bridge nothing" — but the barrier
            // still applies: it lives inside `floodHoriz`/`floodVert`, which always run, and it is
            // not a gap-closing behaviour. That is the one place the option's old contract ("inert
            // at gapRadius 0") deliberately narrows to "inert at gapRadius 0 *and* no padding".
            closedSource = wallBuf
        }
        if let lassoBuf {
            engine.encode2D(enc1, p.floodInitFromLasso, width: width, height: height,
                            buffers: [(closedSource, 0), (regionBuf, 1), (paramsBuf, 2), (lassoBuf, 3)])
        } else {
            engine.encode2D(enc1, p.floodInit, width: width, height: height, buffers: [(closedSource, 0), (regionBuf, 1), (paramsBuf, 2)])
        }
        enc1.endEncoding()
        cb1.commit()

        // Stage 2: parallel scanline flood, in chunks with an early-out convergence check.
        let changedPtr = changedBuf.contents().bindMemory(to: UInt32.self, capacity: 1)
        let maxChunks = 16
        let pairsPerChunk = 4
        for _ in 0..<maxChunks {
            guard let cb = engine.makeCommandBuffer() else { return nil }
            if let blit = cb.makeBlitCommandEncoder() {
                blit.fill(buffer: changedBuf, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
                blit.endEncoding()
            }
            guard let enc = cb.makeComputeCommandEncoder() else { return nil }
            for _ in 0..<pairsPerChunk {
                engine.encode1D(enc, p.floodHoriz, count: height, buffers: [(regionBuf, 0), (closedSource, 1), (paramsBuf, 2), (changedBuf, 3)])
                engine.encode1D(enc, p.floodVert, count: width, buffers: [(regionBuf, 0), (closedSource, 1), (paramsBuf, 2), (changedBuf, 3)])
            }
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            if changedPtr.pointee == 0 { break }
        }

        // Stage 3: edge overlap dilate + paint, then read back.
        guard let cb3 = engine.makeCommandBuffer(), let enc3 = cb3.makeComputeCommandEncoder() else { return nil }
        // **The lasso mode's second half, and the half that makes interior lines vanish.** The flood
        // above only travels through open pixels, so every line the loop encircles is still a hole in
        // the region. Unioning the loop mask back in closes all of them at once — "the line should be
        // filled too, as its boundaries are only the outside encirclement". Done here rather than at
        // seeding time so the walls stay walls *while* the flood runs and the region's outer edge
        // still lands on the artwork.
        if let lassoBuf {
            engine.encode2D(enc3, p.unionMask, width: width, height: height,
                            buffers: [(lassoBuf, 0), (regionBuf, 1), (paramsBuf, 2)])
        }
        let painted: MTLBuffer
        if Int(edgeOverlap.rounded()) >= 1 {
            engine.encode2D(enc3, p.edgeDilate, width: width, height: height, buffers: [(regionBuf, 0), (regionTmpBuf, 1), (paramsBuf, 2)])
            painted = regionTmpBuf
        } else {
            painted = regionBuf
        }
        engine.encode2D(enc3, p.paint, width: width, height: height, buffers: [(painted, 0), (outBuf, 1), (paramsBuf, 2)])
        enc3.endEncoding()
        cb3.commit()
        cb3.waitUntilCompleted()

        var result = [UInt8](repeating: 0, count: count * 4)
        result.withUnsafeMutableBytes { memcpy($0.baseAddress!, outBuf.contents(), count * 4) }
        return result
    }

    // MARK: - JFA helper

    /// Runs a jump-flooding distance transform seeded from `mask == seedValue` and returns whichever
    /// ping-pong buffer holds the final nearest-seed coordinates (thresholded via `encodeThreshold`).
    private func encodeJFA(_ encoder: MTLComputeCommandEncoder, mask: MTLBuffer, seedValue: UInt32) -> MTLBuffer {
        let p = engine.pipelines
        var seed = seedValue
        encoder.setComputePipelineState(p.jfaInit)
        encoder.setBuffer(mask, offset: 0, index: 0)
        encoder.setBuffer(jfaA, offset: 0, index: 1)
        encoder.setBuffer(paramsBuf, offset: 0, index: 2)
        encoder.setBytes(&seed, length: MemoryLayout<UInt32>.size, index: 3)
        engine.dispatch2D(encoder, p.jfaInit, width: width, height: height)

        var src = jfaA, dst = jfaB
        var step = 1
        while step < max(width, height) { step <<= 1 }
        step >>= 1
        while step >= 1 {
            var s = UInt32(step)
            encoder.setComputePipelineState(p.jfaStep)
            encoder.setBuffer(src, offset: 0, index: 0)
            encoder.setBuffer(dst, offset: 0, index: 1)
            encoder.setBuffer(paramsBuf, offset: 0, index: 2)
            encoder.setBytes(&s, length: MemoryLayout<UInt32>.size, index: 3)
            engine.dispatch2D(encoder, p.jfaStep, width: width, height: height)
            swap(&src, &dst)
            step >>= 1
        }
        return src
    }

    private func encodeThreshold(_ encoder: MTLComputeCommandEncoder, from distanceField: MTLBuffer,
                                 out: MTLBuffer, radius: Float, keepInside: UInt32) {
        let p = engine.pipelines
        var r = radius
        var keep = keepInside
        encoder.setComputePipelineState(p.threshold)
        encoder.setBuffer(distanceField, offset: 0, index: 0)
        encoder.setBuffer(out, offset: 0, index: 1)
        encoder.setBuffer(paramsBuf, offset: 0, index: 2)
        encoder.setBytes(&r, length: MemoryLayout<Float>.size, index: 3)
        encoder.setBytes(&keep, length: MemoryLayout<UInt32>.size, index: 4)
        engine.dispatch2D(encoder, p.threshold, width: width, height: height)
    }
}
