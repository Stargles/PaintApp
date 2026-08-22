import Metal
import UIKit
import simd

/// GPU flood-fill engine (see Fill.metal). One `MetalFillEngine` owns the device + compiled kernels;
/// each fill gesture makes a `MetalFillSession` that holds the per-canvas buffers and the composited
/// reference the fill reads its walls from. A fill runs entirely on the GPU — colour-distance wall
/// detection, a jump-flooding disk close for gap bridging, a parallel scanline flood, a disk edge
/// dilate, and the final paint — so it stays real-time regardless of build configuration.
///
/// **Two fills share those stages, and they are not the same algorithm.** The bucket fill seeds one
/// tapped pixel and grows. The lasso fill (a session made with a `lassoMask`) runs LASSO_FILL.md §6:
/// seed the loop's one-pixel ring, flood *inside the loop only*, and paint the loop minus everything
/// that flood could reach. The two halves that make that work are `lassoBarrier` (the flood may not
/// leave the loop) and `lassoInvert` (the intersect that makes the loop a wall and paints over
/// interior line art) — both in Fill.metal. `lassoEdgeErode` runs last on that path and is where the
/// empty check is counted, because Edge Overlap can erase a fill and the count has to know.
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
    private let psFloodInitFromRing: MTLComputePipelineState
    private let psLassoBarrier: MTLComputePipelineState
    private let psLassoInvert: MTLComputePipelineState
    private let psPaintAlpha: MTLComputePipelineState
    private let psLassoEdgeErode: MTLComputePipelineState

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
              let floodInitFromRing = pipeline("floodInitFromRing"),
              let lassoBarrier = pipeline("lassoBarrier"),
              let lassoInvert = pipeline("lassoInvert"),
              let paintAlpha = pipeline("paintRegionAlpha"),
              let lassoEdgeErode = pipeline("lassoEdgeErode") else { return nil }
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
        self.psFloodInitFromRing = floodInitFromRing
        self.psLassoBarrier = lassoBarrier
        self.psLassoInvert = lassoInvert
        self.psPaintAlpha = paintAlpha
        self.psLassoEdgeErode = lassoEdgeErode
    }

    /// Uploads `referenceRGBA` (premultiplied-last, row-major, `width*height*4` bytes) into a session
    /// whose buffers are reused across every fill of the same gesture. Returns nil if allocation fails.
    ///
    /// - Parameter lassoMask: one byte per pixel, non-zero inside the loop the artist drew, for the
    ///   lasso fill type; `nil` is the ordinary bucket fill. Built by `LassoFillMask.rasterize`.
    ///
    ///   **Its presence switches the session to a different algorithm, not merely a different seed**
    ///   (LASSO_FILL.md §6): the mask is the *stencil* the whole operation runs inside, the flood is
    ///   seeded from its one-pixel ring, and the result is the mask minus everything that flood
    ///   reached. The session derives the ring and the reference colours from it here, once, because
    ///   neither can change while the artist drags a slider.
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
                                floodInitFromRing: MTLComputePipelineState,
                                lassoBarrier: MTLComputePipelineState,
                                lassoInvert: MTLComputePipelineState,
                                paintAlpha: MTLComputePipelineState,
                                lassoEdgeErode: MTLComputePipelineState) {
        (psWalls, psJfaInit, psJfaStep, psThreshold, psFloodInit, psFloodHoriz, psFloodVert, psEdgeDilate,
         psPaint, psEdgeBridge, psUnionMask, psFloodInitFromRing, psLassoBarrier, psLassoInvert, psPaintAlpha,
         psLassoEdgeErode)
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
    /// The lasso fill's **stencil** — one byte per pixel, non-zero inside the loop. Nil for an
    /// ordinary bucket fill, and its nil-ness is the switch between the two algorithms.
    ///
    /// Not a seed: `ringBuf` is the seed, this is the region the flood may not leave and the left
    /// operand of the final intersect. See `lassoBarrier` and `lassoInvert` in Fill.metal.
    private let lassoBuf: MTLBuffer?
    /// The loop's one-pixel inner collar, from `LassoFillMask.ringMask` — the collar flood's seeds.
    private let ringBuf: MTLBuffer?
    /// `closed ∨ ¬lasso`: the wall set the collar flood actually runs against, so it can enter the
    /// ring but never leave the loop. One per reference colour, because each has its own walls.
    private let barrierBuf: MTLBuffer?
    /// Second reference colour's walls / closed walls / barrier / reached set, allocated only when
    /// the ring's modal colour is not paper (LASSO_FILL.md §6 2a caps `|C|` at 2).
    private let wall2Buf: MTLBuffer?
    private let closed2Buf: MTLBuffer?
    private let barrier2Buf: MTLBuffer?
    private let region2Buf: MTLBuffer?
    /// 8-bit coverage out of `lassoInvert` — 255 in the fill, the §6 step 6 ramp in the collar.
    private let alphaBuf: MTLBuffer?
    /// Atomic count of the fill's pixels, for the §6 step 5 empty check.
    private let filledBuf: MTLBuffer?
    /// A second `FillParams` differing only in `seedColor`, for the second reference's wall pass.
    private let params2Buf: MTLBuffer?
    private let changedBuf: MTLBuffer
    private let paramsBuf: MTLBuffer

    /// Whether this session runs the lasso algorithm. Immutable, so `drainFillWork` can ask a session
    /// what it is from the fill queue without touching main-thread gesture state.
    let isLasso: Bool

    /// The colours the collar flood may walk through — LASSO_FILL.md §6 2a's `C`, computed once from
    /// the ring. Empty for a bucket fill.
    private(set) var referenceColours: (SIMD4<Float>, SIMD4<Float>?) = (.zero, nil)

    /// Pixels the **last** `fill(...)` painted at full coverage — the artist-visible fill, excluding
    /// the coverage ramp in the collar. Zero means the loop enclosed nothing the artwork held out:
    /// either the collar leaked through a gap or there was no shape inside the loop, which
    /// LASSO_FILL.md §4 case 11 rules are the same outcome. `CanvasManager` commits nothing and
    /// raises a notice on it (§7.1).
    ///
    /// Meaningful only for a lasso session, and only after `fill(...)` returns. Written and read on
    /// `fillQueue`, which is serial and the only place `fill(...)` is called from in the app.
    private(set) var lastFilledPixelCount: Int = 0

    /// The collar's **reached** set from the last `fill(...)` — one byte per pixel, non-zero wherever
    /// the flood seeded at the loop's ring could walk. Nil for a bucket session.
    ///
    /// **What it is for, and the one thing it turns out not to be.** LASSO_FILL.md §7.2 asks that an
    /// empty result show the artist *where the paint went* rather than a blank canvas and a sentence,
    /// on the reasoning that the reached set is the escape route — so on a gap the colour visibly
    /// pours out through it. Krita and Clip Studio Paint ship this algorithm with no such diagnostic
    /// at all and Krita's users report the result as "it just won't fill anything", so the ambition
    /// is right; the mechanics are narrower than §7.2 assumed.
    ///
    /// **On the path where it is displayed, this mask is the loop's whole interior.** The §7 signal
    /// fires only when the fill came back empty, and `lassoInvert` paints every pixel the collar
    /// could *not* reach — ink included, since ink is never passable. So an empty result means
    /// precisely that the collar reached everything, and the tint built from it is congruent to the
    /// fence. It says the true and useful thing for the case it fires on ("everything inside your
    /// loop read as background, so there was nothing to hold out"); it is not the picture of a leak.
    /// A genuine leak is *not* an empty result — the outline's own pixels are unreachable and get
    /// painted, which is `testALeakThroughAWideGapPaintsOnlyTheOutlineTheCollarCouldNotEnter` — so it
    /// announces itself by only the line being coloured, and never reaches this path.
    /// `testTheCollarMaskCarriesTheLeakEvenWhereTheSignalDoesNotFire` pins both halves.
    ///
    /// Read lazily rather than snapshotted inside `fill(...)` because it is wanted only on the empty
    /// path, which is rare, while `fill` runs on every slider tick. The buffers are
    /// `.storageModeShared` and `fill` waits on its last command buffer, so their contents are
    /// settled by the time this can be called — from `fillQueue`, which is the serial queue that ran
    /// the fill and the only place either is touched.
    func lastReachedMask() -> [UInt8]? {
        guard isLasso else { return nil }
        var reached = [UInt8](repeating: 0, count: count)
        let a = regionBuf.contents().bindMemory(to: UInt8.self, capacity: count)
        // The union over `c ∈ C`, matching `lassoInvert`'s own `reached` test exactly — a pixel either
        // reference could walk to is one the artist should see tinted.
        let b = region2Buf?.contents().bindMemory(to: UInt8.self, capacity: count)
        reached.withUnsafeMutableBufferPointer { out in
            for i in 0..<count {
                out[i] = (a[i] != 0 || (b?[i] ?? 0) != 0) ? 255 : 0
            }
        }
        return reached
    }

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
        self.isLasso = lassoMask != nil
        if let lassoMask {
            // The ring and the reference colours are per-*gesture*, not per-render: the loop does not
            // move while the artist drags Threshold or Gap Closing, so deriving them here means a
            // slider sweep re-runs only the GPU stages. It also means production and
            // `LassoFillLogicTests` cannot drift apart on how the ring is defined, because neither
            // computes it — the session does.
            let ring = LassoFillMask.ringMask(lassoMask, width: width, height: height)
            let colours = LassoFillMask.referenceColours(referenceRGBA: referenceRGBA, ring: ring,
                                                         width: width, height: height)
            guard let lasso = lassoMask.withUnsafeBytes({
                      device.makeBuffer(bytes: $0.baseAddress!, length: count, options: .storageModeShared)
                  }),
                  let ringB = ring.withUnsafeBytes({
                      device.makeBuffer(bytes: $0.baseAddress!, length: count, options: .storageModeShared)
                  }),
                  let barrier = buffer(count), let alpha = buffer(count),
                  // **One slot, and `lassoEdgeErode` is the only thing that writes it.** It briefly
                  // held two — `lassoInvert` counting into 0 and the erode recounting into 1 — and the
                  // Swift side then had to choose between them. It chose slot 1 whenever the erode had
                  // run, but the erode's atomic was bound at offset 0 and wrote slot 0, so slot 1 was
                  // never written and every Edge Overlap below the top of the slider reported an empty
                  // fill. The erode now runs on every fill, at radius 0 as an identity copy, so there
                  // is one counter and no choice to get wrong.
                  let filled = buffer(MemoryLayout<UInt32>.stride),
                  let params2 = buffer(MemoryLayout<MetalFillEngine.FillParams>.stride) else { return nil }
            self.lassoBuf = lasso
            self.ringBuf = ringB
            self.barrierBuf = barrier
            self.alphaBuf = alpha
            self.filledBuf = filled
            self.params2Buf = params2
            self.referenceColours = colours
            if colours.1 != nil {
                guard let w2 = buffer(count), let c2 = buffer(count),
                      let b2 = buffer(count), let r2 = buffer(count) else { return nil }
                self.wall2Buf = w2; self.closed2Buf = c2; self.barrier2Buf = b2; self.region2Buf = r2
            } else {
                self.wall2Buf = nil; self.closed2Buf = nil; self.barrier2Buf = nil; self.region2Buf = nil
            }
        } else {
            self.lassoBuf = nil; self.ringBuf = nil; self.barrierBuf = nil; self.alphaBuf = nil
            self.filledBuf = nil; self.params2Buf = nil
            self.wall2Buf = nil; self.closed2Buf = nil; self.barrier2Buf = nil; self.region2Buf = nil
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
    /// **Two algorithms, chosen by whether the session has a lasso mask** (see `makeSession`). The
    /// bucket fill seeds one tapped pixel and grows until walls stop it. The lasso runs
    /// LASSO_FILL.md §6: seed the loop's ring, flood *inside the loop only*, and keep the loop minus
    /// everything that flood reached.
    ///
    /// - Parameter seedColor: the colour the flood treats as the region. **Ignored by a lasso
    ///   session**, which derives its own reference set from the ring at construction — see
    ///   `referenceColours`, and §6 2a for why the loop's whole interior is the wrong input.
    /// - Parameter edgeOverlap: a disk radius in px. **Its direction belongs to the algorithm, not to
    ///   the number**, because the two algorithms end on opposite sides of the artist's line:
    ///   - bucket: the painted region is **grown** by this much, so it runs under the wall it stopped
    ///     against instead of ending inside that wall's antialiasing (`edgeDilate`).
    ///   - lasso: the painted **coverage** is pulled back by this much from the artwork's outer
    ///     silhouette, which it already reaches exactly (`lassoEdgeErode`).
    ///
    ///   Those are the same operation on either side of the lasso's invert, and the lasso's runs on
    ///   the coverage rather than on the collar for one reason: the fill's soft edge is 8 bits of
    ///   alpha that only exists after the invert, so a binary operator upstream cannot carry it. See
    ///   `lassoEdgeErode` for the measurement and LASSO_FILL.md §6 step 7 for the four specifications
    ///   this step has had.
    ///
    ///   0 is identity in both. The Edge Overlap *slider* still reads "up is more colour" in both, and
    ///   `CanvasManager.fillEdgeRadius(lasso:)` is where that becomes a radius: for a lasso it passes
    ///   `fillExpandRange.upperBound - v`, which anchors the top of the slider at the ink's outer edge
    ///   so no setting can put paint on clean paper.
    /// - Parameter canvasEdgeIsWall: make the canvas edge bound the fill. Two mechanisms, both
    ///   described at length above `edgeBridge` in Fill.metal: the artwork rect's boundary becomes a
    ///   **barrier** the flood cannot travel across (unconditional — it does not consult
    ///   `gapRadius`), and gap-closing may additionally **bridge** to that edge so a stroke stopping
    ///   a few px short of it still seals. A lasso session honours both: the artwork rect is a wall
    ///   like any other, and §4 case 10 already treats the canvas edge as part of the fence.
    /// - Parameter edgeInset: px the artwork rect is inset from this buffer on all four sides, i.e.
    ///   `CanvasManager.canvasPadding`. 0 — the default, and what every caller with no padding
    ///   passes — makes the artwork rect the buffer itself, at which point both mechanisms reduce to
    ///   the buffer-rim behaviour the engine had before padding was a consideration. Ignored
    ///   entirely when `canvasEdgeIsWall` is false.
    func fill(seedX: Int, seedY: Int, seedColor: SIMD4<Float>, threshold: Float,
              gapRadius: Float, edgeOverlap: Float, canvasEdgeIsWall: Bool = false,
              edgeInset: Float = 0, fillColor: SIMD4<Float>) -> [UInt8]? {
        // A lasso session works from its mask, so there is no tapped pixel to be in bounds.
        guard isLasso || isSeedInBounds(x: seedX, y: seedY) else { return nil }
        let p = engine.pipelines

        // Reference 0 is the tapped colour for a bucket fill and *paper* for a lasso; reference 1
        // exists only when the lasso's ring sits on something that is not paper.
        let primary = isLasso ? referenceColours.0 : seedColor
        var params = MetalFillEngine.FillParams()
        params.width = UInt32(width); params.height = UInt32(height)
        params.seedX = UInt32(seedX); params.seedY = UInt32(seedY)
        params.threshold = threshold; params.gapRadius = gapRadius; params.edgeOverlap = edgeOverlap
        params.seedColor = primary; params.fillColor = fillColor
        // **One place decides what the option means**, so "off" is provably the pre-padding binary:
        // with `canvasEdgeIsWall` false the shader sees inset 0 and every edge rule collapses to the
        // buffer rim. A degenerate inset (negative, or wide enough to leave no artwork rect at all —
        // a project could load a padding inconsistent with its canvasSize) is treated the same way,
        // because a zero-area rect would fence the flood into nothing.
        let inset = edgeInset.rounded()
        params.edgeInset = (canvasEdgeIsWall && inset > 0 && 2 * inset < Float(min(width, height))) ? inset : 0
        memcpy(paramsBuf.contents(), &params, MemoryLayout<MetalFillEngine.FillParams>.size)
        if let params2Buf, let second = referenceColours.1 {
            var params2 = params
            params2.seedColor = second
            memcpy(params2Buf.contents(), &params2, MemoryLayout<MetalFillEngine.FillParams>.size)
        }

        // Stage 1: walls, gap-closing disk close, flood init.
        guard let cb1 = engine.makeCommandBuffer(), let enc1 = cb1.makeComputeCommandEncoder() else { return nil }
        let closedSource = encodeWallsAndClose(enc1, params: paramsBuf, wall: wallBuf, closed: closedBuf,
                                               gapRadius: gapRadius, canvasEdgeIsWall: canvasEdgeIsWall)
        // The two flood targets. A bucket fill has one; a lasso has one per reference colour, because
        // §6 step 3 defines the reached set as the union of *per-colour* reachability rather than
        // reachability through one merged passable set — a collar may not walk paper → flat → paper.
        var floodPasses: [(region: MTLBuffer, walls: MTLBuffer)] = []
        if let lassoBuf, let ringBuf, let barrierBuf {
            engine.encode2D(enc1, p.lassoBarrier, width: width, height: height,
                            buffers: [(closedSource, 0), (lassoBuf, 1), (paramsBuf, 2), (barrierBuf, 3)])
            engine.encode2D(enc1, p.floodInitFromRing, width: width, height: height,
                            buffers: [(barrierBuf, 0), (regionBuf, 1), (paramsBuf, 2), (ringBuf, 3)])
            floodPasses.append((regionBuf, barrierBuf))
            if let params2Buf, let wall2Buf, let closed2Buf, let barrier2Buf, let region2Buf {
                // Safe to reuse `dilatedBuf`, `bridgeBuf` and the JFA ping-pong here: a compute
                // encoder made by `makeComputeCommandEncoder()` dispatches serially with barriers, so
                // the first pass has finished with all three before this one touches them.
                let closed2 = encodeWallsAndClose(enc1, params: params2Buf, wall: wall2Buf, closed: closed2Buf,
                                                  gapRadius: gapRadius, canvasEdgeIsWall: canvasEdgeIsWall)
                engine.encode2D(enc1, p.lassoBarrier, width: width, height: height,
                                buffers: [(closed2, 0), (lassoBuf, 1), (paramsBuf, 2), (barrier2Buf, 3)])
                engine.encode2D(enc1, p.floodInitFromRing, width: width, height: height,
                                buffers: [(barrier2Buf, 0), (region2Buf, 1), (paramsBuf, 2), (ringBuf, 3)])
                floodPasses.append((region2Buf, barrier2Buf))
            }
        } else {
            engine.encode2D(enc1, p.floodInit, width: width, height: height, buffers: [(closedSource, 0), (regionBuf, 1), (paramsBuf, 2)])
            floodPasses.append((regionBuf, closedSource))
        }
        enc1.endEncoding()
        cb1.commit()

        // Stage 2: parallel scanline flood, in chunks with an early-out convergence check. Both lasso
        // passes share the one `changed` atomic and therefore the one convergence test — they run to
        // the same fixed point either way, and a shared flag just means neither stops early while the
        // other is still moving.
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
                for pass in floodPasses {
                    engine.encode1D(enc, p.floodHoriz, count: height, buffers: [(pass.region, 0), (pass.walls, 1), (paramsBuf, 2), (changedBuf, 3)])
                    engine.encode1D(enc, p.floodVert, count: width, buffers: [(pass.region, 0), (pass.walls, 1), (paramsBuf, 2), (changedBuf, 3)])
                }
            }
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            if changedPtr.pointee == 0 { break }
        }

        // Stage 3: invert then erode (lasso), or edge-overlap dilate (bucket), paint, then read back.
        guard let cb3 = engine.makeCommandBuffer() else { return nil }
        if let filledBuf, let blit = cb3.makeBlitCommandEncoder() {
            blit.fill(buffer: filledBuf, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
            blit.endEncoding()
        }
        guard let enc3 = cb3.makeComputeCommandEncoder() else { return nil }
        if let lassoBuf, let alphaBuf, let filledBuf {
            // **`fill = loopMask ∧ ¬reached`, and it replaced a union of the loop back over the
            // flood.** The old line painted everything the loop enclosed and let the flood carry on
            // outward past it; this one paints what the collar could *not* reach, so the loop bounds
            // the result absolutely and the artwork inside it decides the shape. That swap is the
            // whole of the reported bug's fix, and `lassoInvert`'s own comment explains why the loop
            // must not become a wall to get there.
            var second = referenceColours.1 ?? SIMD4<Float>.zero
            var refCount = UInt32(referenceColours.1 == nil ? 1 : 2)
            // Krita's *Spread*, and 0 is the plain ramp §6 step 6 describes: full opacity only on
            // colour exactly equal to a reference, fading to the fill colour at the threshold. There
            // is no Spread control in this app; the argument is here so adding one is a UI change.
            var spread = Float(0)
            enc3.setComputePipelineState(p.lassoInvert)
            enc3.setBuffer(refBuf, offset: 0, index: 0)
            enc3.setBuffer(lassoBuf, offset: 0, index: 1)
            enc3.setBuffer(paramsBuf, offset: 0, index: 2)
            enc3.setBuffer(regionBuf, offset: 0, index: 3)
            enc3.setBuffer(region2Buf ?? regionBuf, offset: 0, index: 4)
            enc3.setBuffer(alphaBuf, offset: 0, index: 5)
            enc3.setBytes(&second, length: MemoryLayout<SIMD4<Float>>.size, index: 6)
            enc3.setBytes(&refCount, length: MemoryLayout<UInt32>.size, index: 7)
            enc3.setBytes(&spread, length: MemoryLayout<Float>.size, index: 8)
            engine.dispatch2D(enc3, p.lassoInvert, width: width, height: height)
            // **Edge Overlap, and on this path it is an erosion of the coverage** — how far the
            // painted alpha is pulled back inside the artwork's outer silhouette, not how far it is
            // grown past it, with the slider's top of range mapping to 0. `lassoEdgeErode` carries the
            // measurement, the owner's words and the reason it operates here rather than on the collar
            // upstream; `CanvasManager.fillEdgeRadius(lasso:)` does the mapping, because where the top
            // of a slider sits is a UI fact and not the engine's.
            //
            // **Dispatched unconditionally, including at radius 0** where the kernel is an identity
            // copy. That is what makes it the single place the §6 step 5 count is taken: no "did it
            // run?" question, so no second counter slot and no choice between two answers — which is
            // exactly what shipped broken on 2026-08-21.
            //
            // `regionTmpBuf` is the bucket path's scratch and is untouched on this one, so it costs no
            // allocation; the encoder dispatches serially with barriers, so the invert has finished
            // writing `alphaBuf` before this reads it.
            engine.encode2D(enc3, p.lassoEdgeErode, width: width, height: height,
                            buffers: [(alphaBuf, 0), (lassoBuf, 1), (regionTmpBuf, 2), (paramsBuf, 3),
                                      (filledBuf, 4)])
            engine.encode2D(enc3, p.paintAlpha, width: width, height: height,
                            buffers: [(regionTmpBuf, 0), (outBuf, 1), (paramsBuf, 2)])
        } else {
            let painted: MTLBuffer
            if Int(edgeOverlap.rounded()) >= 1 {
                engine.encode2D(enc3, p.edgeDilate, width: width, height: height, buffers: [(regionBuf, 0), (regionTmpBuf, 1), (paramsBuf, 2)])
                painted = regionTmpBuf
            } else {
                painted = regionBuf
            }
            engine.encode2D(enc3, p.paint, width: width, height: height, buffers: [(painted, 0), (outBuf, 1), (paramsBuf, 2)])
        }
        enc3.endEncoding()
        cb3.commit()
        cb3.waitUntilCompleted()

        if let filledBuf {
            // `lassoEdgeErode`'s count, and nothing else's — one slot, one writer, and it runs on
            // every fill, so this is correct at every radius by construction.
            lastFilledPixelCount = Int(filledBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee)
        }
        var result = [UInt8](repeating: 0, count: count * 4)
        result.withUnsafeMutableBytes { memcpy($0.baseAddress!, outBuf.contents(), count * 4) }
        return result
    }

    /// Encodes `computeWalls` for whichever reference `params` carries, then the gap-closing
    /// morphological close, and returns the buffer the flood should treat as wall.
    ///
    /// Factored out because the lasso runs it **once per reference colour** — see `computeWalls`'s
    /// own comment for why the two are not merged into one passability test. `params` is the only
    /// argument that differs between the calls; the JFA helpers keep reading `paramsBuf` because all
    /// they need from it is the canvas dimensions, which are the same either way.
    private func encodeWallsAndClose(_ enc: MTLComputeCommandEncoder, params: MTLBuffer,
                                     wall: MTLBuffer, closed: MTLBuffer,
                                     gapRadius: Float, canvasEdgeIsWall: Bool) -> MTLBuffer {
        let p = engine.pipelines
        engine.encode2D(enc, p.walls, width: width, height: height, buffers: [(refBuf, 0), (wall, 1), (params, 2)])
        guard Int(gapRadius.rounded()) >= 1 else {
            // No *bridge* at a zero radius — the artist has said "bridge nothing" — but the barrier
            // still applies: it lives inside `floodHoriz`/`floodVert`, which always run, and it is
            // not a gap-closing behaviour. That is the one place the option's old contract ("inert
            // at gapRadius 0") deliberately narrows to "inert at gapRadius 0 *and* no padding".
            return wall
        }
        // Dilate: distance to nearest wall <= r.
        let distWall = encodeJFA(enc, mask: wall, seedValue: 1)
        encodeThreshold(enc, from: distWall, out: dilatedBuf, radius: gapRadius, keepInside: 1)
        // The canvas-edge bridge is computed *here*, while `distWall` is still the wall distance
        // field — the erode's own JFA below reuses the same two ping-pong buffers and destroys it.
        // Folded into the closed mask afterwards rather than into `dilatedBuf`, because anything put
        // in there is about to be eroded straight back off.
        if canvasEdgeIsWall {
            engine.encodeBridge(enc, p.edgeBridge, width: width, height: height,
                                coord: distWall, out: bridgeBuf, params: paramsBuf, radius: gapRadius)
        }
        // Erode the dilated mask: distance to nearest background (dilated == 0) > r.
        let distBg = encodeJFA(enc, mask: dilatedBuf, seedValue: 0)
        encodeThreshold(enc, from: distBg, out: closed, radius: gapRadius, keepInside: 0)
        if canvasEdgeIsWall {
            engine.encode2D(enc, p.unionMask, width: width, height: height,
                            buffers: [(bridgeBuf, 0), (closed, 1), (paramsBuf, 2)])
        }
        return closed
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
