import Metal
import UIKit
import simd

/// GPU flood-fill engine (see Fill.metal). One `MetalFillEngine` owns the device + compiled kernels;
/// each fill gesture makes a `MetalFillSession` that holds the per-canvas buffers and the composited
/// reference the fill reads its walls from. A fill is colour-distance wall detection, a feature-transformed
/// distance map to those walls, the basins `FillBasins` partitions the open paper into on the CPU —
/// which are the flood and gap closing at once — their cut for the slider's value on the GPU, a disk
/// edge dilate, and the final paint.
///
/// **Two fills share those stages, and they are not the same algorithm.** The bucket fill reaches
/// what its tapped pixel's basins join. The lasso fill (a session made with a `lassoMask`) runs
/// LASSO_FILL.md §6: seed the loop's one-pixel ring, flood *inside the loop only*, and paint the loop
/// minus everything that flood could reach. The two halves that make that work are `fillDomain` (the
/// flood may not leave the loop) and `lassoInvert` (the intersect that makes the loop a wall and paints
/// over interior line art) — both in Fill.metal. `lassoEdgeErode` runs last on that path and is where the
/// empty check is counted, because Edge Overlap can erase a fill and the count has to know.
///
/// Coordinate convention matches the rest of the app: index 0 is the top-left pixel, y increases
/// downward, 1 unit = 1 pixel. Buffers are laid out as row-major `y * width + x`.
final class MetalFillEngine {
    static let shared = MetalFillEngine()

    let device: MTLDevice
    private let queue: MTLCommandQueue

    /// Every compiled kernel, by the name the stages below call it. A struct rather than a loose
    /// tuple so a kernel is added in one place and read as `p.name`.
    fileprivate struct Pipelines {
        let walls, edtVerticalSeeds, edtHorizontalEnvelope: MTLComputePipelineState
        /// Gap closing (TODO (158)): the distance map `FillBasins` is built from, and its cut.
        let gapLevels, basinRegion: MTLComputePipelineState
        let fillDomain, edgeDilate, paint: MTLComputePipelineState
        let unionMask: MTLComputePipelineState
        let lassoInvert, paintAlpha, lassoEdgeErode: MTLComputePipelineState
        /// Mending (TODO (113)): internal ink gaps and seams to neighboring paint, folded in by `unionMask`.
        let mendSupportClear, mendSupportClassify, mendGap: MTLComputePipelineState

        /// Nil when any kernel is missing from `library`, which is the engine failing to exist.
        init?(device: MTLDevice, library: MTLLibrary) {
            func pipeline(_ name: String) -> MTLComputePipelineState? {
                guard let fn = library.makeFunction(name: name) else { return nil }
                return try? device.makeComputePipelineState(function: fn)
            }
            guard let walls = pipeline("computeWalls"),
                  let edtVerticalSeeds = pipeline("edtVerticalSeeds"),
                  let edtHorizontalEnvelope = pipeline("edtHorizontalEnvelope"),
                  let gapLevels = pipeline("gapLevels"),
                  let basinRegion = pipeline("basinRegion"),
                  let fillDomain = pipeline("fillDomain"),
                  let edgeDilate = pipeline("edgeDilate"),
                  let paint = pipeline("paintRegion"),
                  let unionMask = pipeline("unionMask"),
                  let lassoInvert = pipeline("lassoInvert"),
                  let paintAlpha = pipeline("paintRegionAlpha"),
                  let lassoEdgeErode = pipeline("lassoEdgeErode"),
                  let mendSupportClear = pipeline("mendSupportClear"),
                  let mendSupportClassify = pipeline("mendSupportClassify"),
                  let mendGap = pipeline("mendGap") else { return nil }
            self.walls = walls; self.edtVerticalSeeds = edtVerticalSeeds
            self.edtHorizontalEnvelope = edtHorizontalEnvelope
            self.gapLevels = gapLevels; self.basinRegion = basinRegion
            self.fillDomain = fillDomain
            self.edgeDilate = edgeDilate; self.paint = paint
            self.unionMask = unionMask
            self.lassoInvert = lassoInvert; self.paintAlpha = paintAlpha; self.lassoEdgeErode = lassoEdgeErode
            self.mendSupportClear = mendSupportClear; self.mendSupportClassify = mendSupportClassify
            self.mendGap = mendGap
        }
    }

    fileprivate let pipelines: Pipelines

    /// Mirror of the Metal `FillParams` struct (must match its field order/alignment exactly).
    struct FillParams {
        var width: UInt32 = 0
        var height: UInt32 = 0
        var seedX: UInt32 = 0
        var seedY: UInt32 = 0
        var threshold: Float = 0
        var edgeOverlap: Float = 0
        /// The artwork rect in buffer pixels, `[minX, maxX) x [minY, maxY)` (see Fill.metal). The
        /// buffer itself when the canvas edge is not a boundary.
        var artworkMinX: Float = 0
        var artworkMinY: Float = 0
        var artworkMaxX: Float = 0
        var artworkMaxY: Float = 0
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
        guard let pipelines = Pipelines(device: device, library: library) else { return nil }
        self.device = device
        self.queue = queue
        self.pipelines = pipelines
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
    ///
    /// - Parameter pathWall: premultiplied-last RGBA, carrying the colour a vector stroke's **centre
    ///   line** paints — `StrokeWallMask.mask`, TODO (46). `computeWalls` puts that colour through the
    ///   same threshold test the reference's own pixels get, so the path behaves as if the stroke had
    ///   painted a continuous line — which is what lets a segmented brush enclose a region its dabs
    ///   left gaps in, without taking Threshold's meaning away. `nil` — every raster document, and any
    ///   vector cel with no paint stroke in it — is the pre-(46) fill byte for byte, and copies
    ///   nothing.
    ///
    ///   Per gesture like the lasso mask, and for the same reason: the artwork cannot change while
    ///   the artist drags a slider, so a sweep re-runs only the GPU stages.
    ///
    /// - Parameter gapWidthLimit: the widest gap closing, in working pixels, any `fill` of this session
    ///   will ask for — the top of the slider, at the window's scale. Gap closing's distance map is
    ///   capped where no cut that narrow reads it (`FillBasins.ceiling`), which is what keeps a press
    ///   over a big open fill cheap. Unlimited by default: exact at every width, at full cost.
    func makeSession(referenceRGBA: [UInt8], width: Int, height: Int,
                     lassoMask: [UInt8]? = nil, pathWall: [UInt8]? = nil,
                     gapWidthLimit: Float = .infinity) -> SessionOutcome {
        makeSession(referenceRGBA: referenceRGBA, width: width, height: height,
                    lassoMask: lassoMask, pathWall: pathWall, gapWidthLimit: gapWidthLimit) { ring in
            LassoFillMask.referenceColours(referenceRGBA: referenceRGBA, mask: ring,
                                           width: width, height: height)
        }
    }

    /// A saved fill supplies known covered pixels, rather than a newly drawn lasso's collar. Edge
    /// Overlap can put its contour inside the ink, so sampling that contour would make ink passable.
    /// The source remains the endpoint mask for `mendMask`, not a fence around accepted additions.
    func makeMendSession(referenceRGBA: [UInt8], width: Int, height: Int,
                         sourceMask: [UInt8], pathWall: [UInt8]? = nil) -> SessionOutcome {
        makeSession(referenceRGBA: referenceRGBA, width: width, height: height,
                    lassoMask: sourceMask, pathWall: pathWall, gapWidthLimit: 0) { _ in
            LassoFillMask.referenceColours(referenceRGBA: referenceRGBA, mask: sourceMask,
                                           width: width, height: height)
        }
    }

    /// Complete lasso inputs travel together; there is no bucket/reference-override combination.
    fileprivate struct LassoPreparation {
        let mask: [UInt8]
        let ring: [UInt8]
        let colours: (SIMD4<Float>, SIMD4<Float>?)
    }

    private func makeSession(referenceRGBA: [UInt8], width: Int, height: Int,
                             lassoMask: [UInt8]?, pathWall: [UInt8]?, gapWidthLimit: Float,
                             sampleReferenceColours: ([UInt8]) -> (SIMD4<Float>, SIMD4<Float>?)) -> SessionOutcome {
        let needed = MetalFillSession.predictedBytes(width: width, height: height,
                                                     isLasso: lassoMask != nil)
        guard CompositorBudget.hasHeadroom(for: needed) else {
            return .noHeadroom(needed: needed,
                               available: CompositorBudget.availableMemoryOverrideBytes ?? os_proc_available_memory())
        }
        guard width > 0, height > 0, width <= 16_383, height <= 16_383,
              referenceRGBA.count >= width * height * 4,
              lassoMask.map({ $0.count >= width * height }) ?? true,
              pathWall.map({ $0.count >= width * height * 4 }) ?? true else {
            return .unavailable(needed: needed)
        }
        // Preparation follows the shared refusal checks, so a known budget refusal allocates no ring.
        let lasso = lassoMask.map { mask in
            let ring = LassoFillMask.ringMask(mask, width: width, height: height)
            return LassoPreparation(mask: mask, ring: ring, colours: sampleReferenceColours(ring))
        }
        guard let session = MetalFillSession(engine: self, referenceRGBA: referenceRGBA,
                                             width: width, height: height,
                                             lasso: lasso, pathWall: pathWall,
                                             gapWidthLimit: gapWidthLimit) else {
            return .unavailable(needed: needed)
        }
        return .ready(session)
    }

    /// **What one fill gesture may allocate** — BUGS.md's census item 3, which found the fill path
    /// with "no budget and no headroom check at all", and RENDER.md §5 stage 7.
    ///
    /// MEASURED on an iOS 26.5 simulator, 2026-09-06, summed off `MTLBuffer.length`: a bucket session
    /// is **38.0 bytes per working pixel** and a lasso one **42.0** (46 with two reference colours).
    /// (The census read ~34 and 44 out of the source; the four it missed are the CPU copy of the
    /// reference the session keeps for `seedColor(atX:y:)`.) TODO (113)'s neighbour mask added one
    /// byte to each — 39, 43 and 47 — which is read off the buffer list rather than re-measured, and
    /// held to the allocation by the same budget test that held the first figure.
    ///
    /// **Borrowed from `CompositorBudget` rather than invented**, like every other budget in the app:
    /// a fill session is a transient working set held *beside* the document, the compositor's
    /// textures and the caches, so it should scale with the device on the one rule they all use. On
    /// the owner's iPad 9 that is 183.7 MB.
    ///
    /// **Since TODO (86) this is a budget on the *window* a fill works in, never on the canvas**:
    /// `FillWindow` sizes every buffer of a gesture to the region being filled and scales the window
    /// down when the region alone exceeds this, so no canvas is too large to fill and `makeSession`
    /// has no static refusal left. What remains here is the valve — `hasHeadroom` is dynamic and says
    /// whether *right now* is the moment: a fill the budget allows can still be declined because
    /// another app took the memory.
    static var fillBudgetBytes: Int { CompositorBudget.textureBudgetBytes }

    /// The most working pixels a window may hold and still fit `fillBudgetBytes` — what `FillWindow`
    /// sizes itself against. Priced at the dearest session of its kind, since a lasso's second
    /// reference colour is not knowable before the window is cut.
    static func workingPixelBudget(isLasso: Bool) -> Int {
        max(1, fillBudgetBytes / MetalFillSession.bytesPerPixel(isLasso: isLasso, twoReferenceColours: true))
    }

    /// What `makeSession` decided, and **why**, because the ways it can fail are different things to
    /// tell the artist and returning nil for all of them told them nothing at all. Before this the
    /// 16383² case was `makeBuffer` answering nil inside a `guard`, so the fill tool simply did not
    /// work and said so nowhere — CLAUDE.md's "a refusal with no notice", reached by a door nobody
    /// had checked.
    enum SessionOutcome {
        case ready(MetalFillSession)
        /// The window is within budget but the process cannot afford the allocation at this moment.
        case noHeadroom(needed: Int, available: Int)
        /// Metal declined, or the arguments do not describe a canvas.
        case unavailable(needed: Int)

        /// The session, or nil — for the tests and benches that only care whether one was made.
        var session: MetalFillSession? {
            if case .ready(let session) = self { return session }
            return nil
        }

        /// Whether the artist should be told. Every non-`ready` outcome means the fill they asked for
        /// is not going to happen, and every one of them used to be silent.
        var isRefusal: Bool { session == nil }
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

    fileprivate func encodeNearestFeatures(_ encoder: MTLComputeCommandEncoder, width: Int, height: Int,
                                           wall: MTLBuffer, wall2: MTLBuffer,
                                           params: MTLBuffer, refCount: UInt32,
                                           targetsInk: UInt32, workspace: MTLBuffer, result: MTLBuffer) {
        let p = pipelines
        var refs = refCount, inkFlag = targetsInk
        encoder.setComputePipelineState(p.edtVerticalSeeds)
        encoder.setBuffer(wall, offset: 0, index: 0)
        encoder.setBuffer(wall2, offset: 0, index: 1)
        encoder.setBuffer(params, offset: 0, index: 2)
        encoder.setBytes(&refs, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&inkFlag, length: MemoryLayout<UInt32>.size, index: 4)
        encoder.setBuffer(workspace, offset: 0, index: 5)
        let verticalThreads = min(64, p.edtVerticalSeeds.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: width, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: verticalThreads, height: 1, depth: 1))

        encoder.setComputePipelineState(p.edtHorizontalEnvelope)
        encoder.setBuffer(workspace, offset: 0, index: 0)
        encoder.setBuffer(workspace, offset: width * height * MemoryLayout<Int32>.stride, index: 1)
        encoder.setBuffer(result, offset: 0, index: 2)
        encoder.setBuffer(params, offset: 0, index: 3)
        let horizontalThreads = min(64, p.edtHorizontalEnvelope.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: 1, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: horizontalThreads, depth: 1))
    }

    /// Convenience for kernels that only need buffer arguments (no `setBytes`).
    fileprivate func encode2D(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                              width: Int, height: Int, buffers: [(MTLBuffer, Int)]) {
        encoder.setComputePipelineState(pipeline)
        for (buf, index) in buffers { encoder.setBuffer(buf, offset: 0, index: index) }
        dispatch2D(encoder, pipeline, width: width, height: height)
    }

    fileprivate func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }
}

/// Per-gesture GPU buffers + the composited reference. `fill(...)` runs the whole pipeline and returns
/// the painted region as premultiplied RGBA bytes (transparent where unfilled), ready to composite
/// onto the destination layer.
final class MetalFillSession {
    private let engine: MetalFillEngine
    let width: Int
    let height: Int
    private let count: Int

    private struct MendSupportBuffers {
        let patches: MTLBuffer, contacts: MTLBuffer, spans: MTLBuffer
        let patchCount: UInt32
        var bytes: Int { patches.length + contacts.length + spans.length }
    }
    private enum VectorSupport {
        case waiting(VectorMendSupport.Reference)
        case ready(MendSupportBuffers)
        case unavailable
    }
    private var vectorSupport = VectorSupport.unavailable
    /// Exact completed SOURCE cut. Structure/neighbour/workspace writes invalidate it before encoding.
    /// The serial session is the sole owner; no float slider value stands in for these table bytes.
    private var completedMendCut: [[UInt8]]?

    func installVectorReference(_ reference: VectorMendSupport.Reference) {
        completedMendCut = nil
        vectorSupport = .unavailable
        let bytes = reference.retainedBytes
        guard reference.width == width, reference.height == height,
              bytes <= MetalFillEngine.fillBudgetBytes - allocatedBytes,
              CompositorBudget.hasHeadroom(for: bytes) else { return }
        vectorSupport = .waiting(reference)
    }

    private var supportBuffers: MendSupportBuffers? {
        if case .ready(let buffers) = vectorSupport { return buffers }
        return nil
    }

    /// Geometry is built once for this frozen reference/window, outside Structure's threshold owner.
    /// Refusal disables only new interior eligibility; ordinary fill and the neighbour seam continue.
    private func prepareVectorSupport() {
        guard case .waiting(let reference) = vectorSupport else { return }
        vectorSupport = .unavailable
        // Keep construction and uploaded rows beside each other, plus two current/old source cuts.
        let cutReserve = count * (isLasso ? 4 : 2) + 512
        let available = max(0, MetalFillEngine.fillBudgetBytes - allocatedBytes - cutReserve - reference.retainedBytes)
        let budget = available / 2
        guard budget > 0 else { return }
        // A completed packet already owns its CPU rows. The native lazy constructor still
        // needs its construction allowance; prepared rows only need the actual upload below.
        if reference.preparedPacket == nil,
           !CompositorBudget.hasHeadroom(for: available + cutReserve) { return }
        do throws(VectorMendSupport.Failure) {
            let packet: VectorMendSupport.Packet
            if let prepared = reference.preparedPacket { packet = prepared }
            else { packet = try VectorMendSupport.produce(reference, admission: .init(bytes: budget, work: 64_000_000)) }
            guard !packet.patches.isEmpty else { return }
            let uploadBytes = [max(4, UndoBudget.payloadBytes(count: packet.patches.count,
                                                            stride: MemoryLayout<VectorMendSupport.Patch>.stride)),
                               max(4, UndoBudget.payloadBytes(count: packet.contacts.count,
                                                            stride: MemoryLayout<VectorMendSupport.Contact>.stride)),
                               max(4, UndoBudget.payloadBytes(count: packet.canonicalCoverage.count,
                                                            stride: MemoryLayout<VectorMendSupport.Span>.stride))]
                .reduce(0, UndoBudget.addingCost)
            guard uploadBytes <= available, CompositorBudget.hasHeadroom(for: uploadBytes) else { return }
            func upload<T>(_ rows: [T]) -> MTLBuffer? {
                let (length, overflow) = rows.count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
                guard !overflow else { return nil }
                if length == 0 { return engine.device.makeBuffer(length: 4, options: .storageModeShared) }
                return rows.withUnsafeBytes {
                    engine.device.makeBuffer(bytes: $0.baseAddress!, length: length, options: .storageModeShared)
                }
            }
            guard let patches = upload(packet.patches), let contacts = upload(packet.contacts),
                  let spans = upload(packet.canonicalCoverage) else { return }
            let buffers = MendSupportBuffers(patches: patches, contacts: contacts, spans: spans,
                                            patchCount: UInt32(packet.patches.count))
            guard buffers.bytes <= available, allocatedBytes + buffers.bytes + cutReserve <= MetalFillEngine.fillBudgetBytes else { return }
            vectorSupport = .ready(buffers)
        } catch { return }
    }

    private func encodeMendSupport(_ enc: MTLComputeCommandEncoder, source: MTLBuffer,
                                   refCount: UInt32, fence: MTLBuffer?) {
        let p = engine.pipelines
        engine.encode2D(enc, p.mendSupportClear, width: width, height: height,
                        buffers: [(featureWorkspace, 0), (paramsBuf, 1)])
        guard let support = supportBuffers else { return }
        var references = refCount, hasFence = UInt32(fence == nil ? 0 : 1), patches = support.patchCount
        enc.setComputePipelineState(p.mendSupportClassify)
        for (buffer, slot) in [(support.patches, 0), (support.contacts, 1), (support.spans, 2),
                               (source, 3), (wallBuf, 4), (wall2Buf ?? wallBuf, 5),
                               (neighbourBuf, 6), (fence ?? wallBuf, 7), (featureWorkspace, 8), (paramsBuf, 9)] {
            enc.setBuffer(buffer, offset: 0, index: slot)
        }
        enc.setBytes(&references, length: MemoryLayout<UInt32>.stride, index: 10)
        enc.setBytes(&hasFence, length: MemoryLayout<UInt32>.stride, index: 11)
        enc.setBytes(&patches, length: MemoryLayout<UInt32>.stride, index: 12)
        engine.dispatch2D(enc, p.mendSupportClassify, width: Int(patches), height: 1)
    }

    /// CPU copy of the reference, kept so the seed colour can be sampled without a GPU round-trip.
    private let referenceRGBA: [UInt8]

    private let refBuf: MTLBuffer
    /// **TODO (46)'s path wall** — premultiplied-last RGBA, carrying the colour a vector stroke's
    /// centre line paints, so `computeWalls` can put the path through the same threshold test the
    /// painted pixels get and a segmented brush encloses a region its dabs do not. Always allocated
    /// because Metal has no unbound argument; all zeros when there is none, which is every raster
    /// document. `StrokeWallMask` builds it and says which strokes count.
    private let pathWallBuf: MTLBuffer
    /// Whether `pathWallBuf` holds anything — for a test that wants to prove a session was handed one
    /// rather than inferring it from the pixels it produced. Nothing in the render path reads it.
    let hasPathWall: Bool
    private let wallBuf: MTLBuffer
    /// **The optional neighbour set** (TODO (113)): one byte a pixel, non-zero wherever something is
    /// already painted on the cel this fill lands on — the paint the seam branch can join, and anything
    /// else that layer holds. Always allocated, for `pathWallBuf`'s reason (Metal has no unbound
    /// argument), and zero until `installNeighbours`. Internal mending uses it to protect existing paint.
    private let neighbourBuf: MTLBuffer
    /// Whether `installNeighbours` has run, so the caller builds the mask once per session rather than
    /// once per slider tick.
    private(set) var hasNeighbours = false
    /// The region `FillBasins`' cut reached for the current slider value — rewritten by every call, and
    /// the domain the basins are built over (`fillDomain`) while they are being built. Read by the lasso's
    /// invert and by `lastReachedMask()`; what gets painted is built in `regionTmpBuf`.
    private let regionBuf: MTLBuffer
    private let regionTmpBuf: MTLBuffer
    /// The transform workspace and coordinate output. During basin construction the output is scratch;
    /// on the first mend it becomes the cached nearest-open map, while the workspace is mend output.
    private let featureWorkspace: MTLBuffer
    private let featureCoordinates: MTLBuffer
    /// Each pixel's basin, from `FillBasins` — what the slider's cut is a table over. One per flood
    /// pass, like the reached sets: `labels2Buf` exists only beside the lasso's second reference.
    private let labelsBuf: MTLBuffer
    private let outBuf: MTLBuffer
    /// The lasso fill's **stencil** — one byte per pixel, non-zero inside the loop. Nil for an
    /// ordinary bucket fill, and its nil-ness is the switch between the two algorithms.
    ///
    /// Not a seed: `ringBuf` is the seed, this is the region the flood may not leave and the left
    /// operand of the final intersect. See `fillDomain` and `lassoInvert` in Fill.metal.
    private let lassoBuf: MTLBuffer?
    /// The loop's one-pixel inner collar, from `LassoFillMask.ringMask` — the collar flood's seeds.
    private let ringBuf: MTLBuffer?
    /// Second reference colour's walls / reached set / basins, allocated only when the sampled modal
    /// colour is not paper (LASSO_FILL.md §6 2a caps `|C|` at 2).
    private let wall2Buf: MTLBuffer?
    private let region2Buf: MTLBuffer?
    private let labels2Buf: MTLBuffer?
    /// 8-bit coverage out of `lassoInvert` — 255 in the fill, the §6 step 6 ramp in the collar.
    private let alphaBuf: MTLBuffer?
    /// Atomic count of the fill's pixels, for the §6 step 5 empty check.
    private let filledBuf: MTLBuffer?
    /// A second `FillParams` differing only in `seedColor`, for the second reference's wall pass.
    private let params2Buf: MTLBuffer?
    private let paramsBuf: MTLBuffer

    /// Whether this session runs the lasso algorithm. Immutable, so `renderFill` can ask a session
    /// what it is from the fill queue without touching main-thread gesture state.
    let isLasso: Bool

    /// LASSO_FILL.md §6 2a's paper/modal references, computed once from a new lasso's ring or a saved
    /// fill's known coverage. Empty for a bucket fill.
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

    /// The widest gap closing this session is built for — see `makeSession`.
    private let gapWidthLimit: Float

    fileprivate init?(engine: MetalFillEngine, referenceRGBA: [UInt8], width: Int, height: Int,
                      lasso: MetalFillEngine.LassoPreparation?, pathWall: [UInt8]?, gapWidthLimit: Float) {
        let count = width * height
        let device = engine.device
        func buffer(_ bytes: Int) -> MTLBuffer? { device.makeBuffer(length: max(bytes, 4), options: .storageModeShared) }
        guard let refBuf = referenceRGBA.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * 4, options: .storageModeShared) }),
              let wallBuf = buffer(count), let neighbourBuf = buffer(count),
              let regionBuf = buffer(count), let regionTmpBuf = buffer(count),
              let featureWorkspace = buffer(count * MemoryLayout<SIMD2<Int32>>.stride),
              let featureCoordinates = buffer(count * MemoryLayout<SIMD2<Int32>>.stride),
              let labelsBuf = buffer(count * MemoryLayout<Int32>.stride),
              let outBuf = buffer(count * 4),
              let paramsBuf = buffer(MemoryLayout<MetalFillEngine.FillParams>.stride) else { return nil }
        // **An RGBA buffer is bound at index 3 of `computeWalls` on every fill**, because Metal has no
        // such thing as an unbound argument: the alternative to always having one is a second
        // pipeline, or a function constant, for a kernel that costs one extra texel read. When there
        // is no path wall this is `count * 4` zero bytes — 8 MiB at 2048x1024, beside the `count * 4`
        // output buffer and two `count * 8` feature-transform buffers this session already holds — and the
        // kernel's answer is unchanged, since alpha 0 fails its own test.
        guard let pathWallBuf = buffer(count * 4) else { return nil }
        if let pathWall {
            pathWall.withUnsafeBytes { memcpy(pathWallBuf.contents(), $0.baseAddress!, count * 4) }
        } else {
            memset(pathWallBuf.contents(), 0, count * 4)
        }
        memset(neighbourBuf.contents(), 0, max(count, 4))
        self.neighbourBuf = neighbourBuf
        self.pathWallBuf = pathWallBuf
        self.hasPathWall = pathWall != nil
        self.engine = engine
        self.gapWidthLimit = gapWidthLimit
        self.width = width
        self.height = height
        self.count = count
        self.isLasso = lasso != nil
        if let lasso {
            let colours = lasso.colours
            guard let lassoB = lasso.mask.withUnsafeBytes({
                      device.makeBuffer(bytes: $0.baseAddress!, length: count, options: .storageModeShared)
                  }),
                  let ringB = lasso.ring.withUnsafeBytes({
                      device.makeBuffer(bytes: $0.baseAddress!, length: count, options: .storageModeShared)
                  }),
                  let alpha = buffer(count),
                  // **One slot, and `lassoEdgeErode` is the only thing that writes it.** It briefly
                  // held two — `lassoInvert` counting into 0 and the erode recounting into 1 — and the
                  // Swift side then had to choose between them. It chose slot 1 whenever the erode had
                  // run, but the erode's atomic was bound at offset 0 and wrote slot 0, so slot 1 was
                  // never written and every Edge Overlap below the top of the slider reported an empty
                  // fill. The erode now runs on every fill, at radius 0 as an identity copy, so there
                  // is one counter and no choice to get wrong.
                  let filled = buffer(MemoryLayout<UInt32>.stride),
                  let params2 = buffer(MemoryLayout<MetalFillEngine.FillParams>.stride) else { return nil }
            self.lassoBuf = lassoB
            self.ringBuf = ringB
            self.alphaBuf = alpha
            self.filledBuf = filled
            self.params2Buf = params2
            self.referenceColours = colours
            if colours.1 != nil {
                guard let w2 = buffer(count), let r2 = buffer(count),
                      let l2 = buffer(count * MemoryLayout<Int32>.stride) else { return nil }
                self.wall2Buf = w2; self.region2Buf = r2; self.labels2Buf = l2
            } else {
                self.wall2Buf = nil; self.region2Buf = nil; self.labels2Buf = nil
            }
        } else {
            self.lassoBuf = nil; self.ringBuf = nil; self.alphaBuf = nil
            self.filledBuf = nil; self.params2Buf = nil
            self.wall2Buf = nil; self.region2Buf = nil; self.labels2Buf = nil
        }
        self.referenceRGBA = referenceRGBA
        self.refBuf = refBuf
        self.wallBuf = wallBuf
        self.regionBuf = regionBuf
        self.regionTmpBuf = regionTmpBuf
        self.featureWorkspace = featureWorkspace
        self.featureCoordinates = featureCoordinates
        self.labelsBuf = labelsBuf
        self.outBuf = outBuf
        self.paramsBuf = paramsBuf
    }

    /// **Every `MTLBuffer` this session holds, summed off `MTLBuffer.length`** — what a fill gesture
    /// costs, from the objects rather than from arithmetic about them.
    ///
    /// The buffers are `.storageModeShared`, so this is resident the moment the session exists rather
    /// than lazily faulted the way a `CGBitmapContext` is (PERFORMANCE.md §9 item 8) — which is what
    /// makes it the one site in BUGS.md's census whose `w·h·4` column *understates*.
    ///
    /// The CPU copy of the reference is counted too: `referenceRGBA` is held for the life of the
    /// session so `seedColor(atX:y:)` needs no round trip, and it is another `count * 4`. Lazy vector
    /// reference metadata, uploaded rows, basin tables and the retained SOURCE cut are included
    /// when those owners exist. Their sizes depend on actual records rather than just the window.
    var allocatedBytes: Int {
        let required = [refBuf, pathWallBuf, wallBuf, neighbourBuf, regionBuf, regionTmpBuf,
                        featureWorkspace, featureCoordinates, labelsBuf, outBuf, paramsBuf]
        let optional = [lassoBuf, ringBuf, alphaBuf, filledBuf, params2Buf, wall2Buf, region2Buf, labels2Buf]
        return required.reduce(0) { $0 + $1.length }
            + optional.reduce(0) { $0 + ($1?.length ?? 0) }
            + referenceRGBA.count
            + (supportBuffers?.bytes ?? 0)
            + { if case .waiting(let reference) = vectorSupport { return reference.retainedBytes }; return 0 }()
            + (completedMendCut.map { cut in
                cut.capacity * MemoryLayout<[UInt8]>.stride + 32 + cut.reduce(0) { $0 + $1.capacity + 32 }
            } ?? 0)
            + (structure?.passes.reduce(0) { $0 + $1.table.length } ?? 0)
    }

    /// **What a session of this shape will cost, before a byte of it is allocated** — the number
    /// `MetalFillEngine.makeSession` weighs against the budget.
    ///
    /// Derived from the same buffer list `allocatedBytes` sums, and
    /// `MetalFillBudgetLogicTests.testThePredictedCostIsWhatASessionActuallyAllocates` pins the two
    /// equal on a real device. A prediction that drifted from the allocation would be a budget about
    /// a session nobody makes.
    ///
    /// - Parameter twoReferenceColours: whether the lasso's ring resolves to two colours rather than
    ///   one (LASSO_FILL.md §6 2a caps `|C|` at 2), which is three more `count`-sized buffers. Not
    ///   knowable before the ring is built, so the budget assumes the worst case for a lasso.
    static func predictedBytes(width: Int, height: Int, isLasso: Bool,
                               twoReferenceColours: Bool = true) -> Int {
        let count = max(0, width) * max(0, height)
        var bytes = count * bytesPerPixel(isLasso: isLasso, twoReferenceColours: twoReferenceColours)
        // The one that does not scale — a `FillParams` — which is here so the prediction is exact
        // rather than nearly right. A budget that is "close" is a budget a test cannot pin against the
        // allocation.
        bytes += MemoryLayout<MetalFillEngine.FillParams>.stride
        if isLasso {
            // A second `FillParams` and the filled-pixel counter.
            bytes += MemoryLayout<UInt32>.stride + MemoryLayout<MetalFillEngine.FillParams>.stride
        }
        return bytes
    }

    /// What every working pixel of a session costs, summed off the buffer list `allocatedBytes` sums.
    static func bytesPerPixel(isLasso: Bool, twoReferenceColours: Bool) -> Int {
        // refBuf, pathWallBuf, outBuf: 4 bytes a pixel each. wall/neighbour/region/regionTmp: 1 each.
        // featureWorkspace/featureCoordinates: 8 each. The basin labels: 4. Plus the CPU reference copy at 4. **40 a pixel**,
        // equal to `allocatedBytes` by
        // `MemoryBudgetLogicTests.testAFillSessionsPredictedCostIsWhatItActuallyAllocates`.
        var bytes = (4 + 4 + 4) + 4 + 16 + 4 + 4
        if isLasso {
            // lasso, ring, alpha: 1 byte a pixel each.
            bytes += 3
            // wall2 and region2 at 1 each, and labels2 at 4, only when the ring holds two colours —
            // which is not knowable until the ring is built, so the budget assumes the worst case. A
            // lasso session over a uniform reference resolves to one colour and allocates 43 bytes a
            // pixel rather than 49; the prediction may only over-estimate, never under.
            if twoReferenceColours { bytes += 2 + 4 }
        }
        return bytes
    }

    /// This buffer as a rect — what `fill(artworkRect:)` is handed when the canvas edge bounds the
    /// fill and the buffer *is* the canvas, which is every fixture in the logic tier.
    var bufferRect: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    /// The straight-RGBA colour at `(x, y)` in the reference (0..1), used as the flood seed colour.
    func seedColor(atX x: Int, y: Int) -> SIMD4<Float> {
        guard x >= 0, x < width, y >= 0, y < height else { return .zero }
        let o = (y * width + x) * 4
        return SIMD4<Float>(Float(referenceRGBA[o]), Float(referenceRGBA[o + 1]),
                            Float(referenceRGBA[o + 2]), Float(referenceRGBA[o + 3])) / 255.0
    }

    /// Hands the session the pixels already painted on the cel this fill lands on, for the fill-to-fill seam branch
    /// (TODO (113)): one byte per working pixel, non-zero where something is. Once per session — the
    /// cel cannot change while a fill is adjustable, since every edit settles it first.
    ///
    /// **The set is "whatever is on this cel", not "the fills on this cel", and that is a decision
    /// rather than a limit.** A raster layer flattens a committed fill into the same tier as its
    /// brush strokes, so a fill is not recoverable as such, and the rule that falls out is the safe
    /// one: a seam grows toward paint that is already on the layer and never over it. Line art on
    /// the layer being filled is therefore a neighbour too, which is a no-op in practice — a fill
    /// already runs up to the ink it stopped against.
    func installNeighbours(_ mask: [UInt8]) {
        guard mask.count >= count else { return }
        completedMendCut = nil
        mask.withUnsafeBytes { memcpy(neighbourBuf.contents(), $0.baseAddress!, count) }
        hasNeighbours = true
    }

    /// Mends a saved fill path as a new operation using the session's current sampled reference colours.
    /// Returns only the added pixels, leaving Boolean union and path reconstruction to the caller.
    func mendMask(sourceMask: [UInt8], threshold: Float, artworkRect: CGRect?, reach: Float) -> [UInt8]? {
        guard isLasso, sourceMask.count >= count, reach >= 1,
              reach <= Float(ceil(CanvasManager.fillMendReachRange.upperBound)) else { return nil }
        // This independent preparation rewrites the walls and feature buffers shared with fill.
        // Drop their old owner before any write, including a preparation that later refuses.
        structure = nil
        completedMendCut = nil
        prepareVectorSupport()
        sourceMask.withUnsafeBytes { memcpy(regionBuf.contents(), $0.baseAddress!, count) }
        var params = MetalFillEngine.FillParams()
        params.width = UInt32(width); params.height = UInt32(height)
        params.threshold = threshold
        params.seedColor = referenceColours.0
        let boundary = artworkRect.map { $0.integral }.flatMap { $0.isEmpty ? nil : $0 }
        let paper = boundary ?? bufferRect
        params.artworkMinX = Float(paper.minX); params.artworkMinY = Float(paper.minY)
        params.artworkMaxX = Float(paper.maxX); params.artworkMaxY = Float(paper.maxY)
        memcpy(paramsBuf.contents(), &params, MemoryLayout<MetalFillEngine.FillParams>.size)
        if let params2Buf, let second = referenceColours.1 {
            var params2 = params
            params2.seedColor = second
            memcpy(params2Buf.contents(), &params2, MemoryLayout<MetalFillEngine.FillParams>.size)
        }
        guard let cb = engine.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return nil }
        let p = engine.pipelines
        engine.encode2D(enc, p.walls, width: width, height: height,
                        buffers: [(refBuf, 0), (wallBuf, 1), (paramsBuf, 2), (pathWallBuf, 3)])
        if let params2Buf, let wall2Buf, referenceColours.1 != nil {
            engine.encode2D(enc, p.walls, width: width, height: height,
                            buffers: [(refBuf, 0), (wall2Buf, 1), (params2Buf, 2), (pathWallBuf, 3)])
        }
        if supportBuffers != nil { encodeNearestOpenFeatures(enc) }
        encodeMendSupport(enc, source: regionBuf, refCount: referenceColours.1 == nil ? 1 : 2, fence: nil)
        encodeMend(enc, painted: regionBuf, source: regionBuf, reach: reach,
                   refCount: referenceColours.1 == nil ? 1 : 2,
                   nearestOpen: featureCoordinates, fence: nil, mergeIntoPainted: false)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        guard cb.status == .completed else { return nil }
        let bytes = featureWorkspace.contents().bindMemory(to: UInt8.self, capacity: count)
        return Array(UnsafeBufferPointer(start: bytes, count: count))
    }

    /// Whether the reference pixel at the seed is opaque enough / distinct — currently always fills;
    /// kept as a hook mirroring the old engine's "tapped on ink" guard.
    func isSeedInBounds(x: Int, y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    /// Runs the pipeline and returns the painted region as premultiplied RGBA (row-major,
    /// `width*height*4`), transparent where unfilled. `fillColor` is premultiplied 0..1.
    ///
    /// **Two algorithms, chosen by whether the session has a lasso mask** (see `makeSession`). The
    /// bucket fill seeds one tapped pixel and grows until walls stop it. The lasso runs
    /// LASSO_FILL.md §6: seed the loop's ring, flood *inside the loop only*, and keep the loop minus
    /// everything that flood reached.
    ///
    /// **The work splits by what can change it.** The walls, the distance map and its basins depend on
    /// the seed, the threshold and the paper — `Structure` — and are kept between calls; a call that
    /// changes only Gap Closing, Edge Overlap, the mend or the colour re-runs the basin cut and the
    /// paint, which is what makes the slider live (TODO (158), (157)).
    ///
    /// - Parameter seedColor: the colour the flood treats as the region. **Ignored by a lasso
    ///   session**, which derives its own reference set from the ring at construction — see
    ///   `referenceColours`, and §6 2a for why the loop's whole interior is the wrong input.
    /// - Parameter gapWidth: the widest opening, in working pixels, that gap closing seals — the
    ///   number on the slider. Below 1 nothing is sealed and the fill is the plain flood. See
    ///   `FillBasins` for what counts as an opening, and why an edge or a corner never does.
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
    /// - Parameter artworkRect: the paper's rect in **this buffer's** pixels, when the canvas edge
    ///   bounds the fill; nil when it does not. Two mechanisms, both described above `gapLevels` in
    ///   Fill.metal: the rect's boundary becomes a **barrier** the flood cannot travel across
    ///   (unconditional — it does not consult `gapWidth`), and the paper's edge counts as **ink** for
    ///   gap closing, so a stroke stopping a few px short of it leaves an opening that seals.
    ///   A lasso session honours both: the artwork rect is a wall like any other, and §4 case 10
    ///   already treats the canvas edge as part of the fence. The rect may extend past the buffer —
    ///   the buffer is a window of the canvas (`FillWindow`) — and a degenerate one is treated as
    ///   nil, because a zero-area rect would fence the flood into nothing.
    /// - Parameter mendReach: the maximum ink width mended, in working pixels, counted from the fill
    ///   after Edge Overlap. The internal-gap branch requires source fill on both sides of an ink
    ///   run; `installNeighbours` additionally enables closing seams to existing paint (TODO (113)).
    ///   0 is no mend. Without an installed neighbour mask, only the internal-gap branch is active.
    func fill(seedX: Int, seedY: Int, seedColor: SIMD4<Float>, threshold: Float,
              gapWidth: Float, edgeOverlap: Float, artworkRect: CGRect? = nil,
              mendReach: Float = 0, fillColor: SIMD4<Float>) -> [UInt8]? {
        // A lasso session works from its mask, so there is no tapped pixel to be in bounds.
        guard (isLasso || isSeedInBounds(x: seedX, y: seedY)),
              mendReach <= Float(ceil(CanvasManager.fillMendReachRange.upperBound)) else { return nil }
        let p = engine.pipelines

        // Reference 0 is the tapped colour for a bucket fill and *paper* for a lasso; reference 1
        // exists only when the lasso's ring sits on something that is not paper.
        let primary = isLasso ? referenceColours.0 : seedColor
        var params = MetalFillEngine.FillParams()
        params.width = UInt32(width); params.height = UInt32(height)
        params.seedX = UInt32(seedX); params.seedY = UInt32(seedY)
        params.threshold = threshold; params.edgeOverlap = edgeOverlap
        params.seedColor = primary; params.fillColor = fillColor
        // **One place decides what the option means**, so "off" is provably the pre-padding binary:
        // without a rect the shader sees the buffer itself and every edge rule collapses to its rim.
        // A degenerate rect (empty, or one a project loaded with a padding inconsistent with its
        // canvasSize) is treated the same way, because a zero-area rect would fence the flood into
        // nothing.
        let boundary = artworkRect.map { $0.integral }.flatMap { $0.isEmpty ? nil : $0 }
        let paper = boundary ?? bufferRect
        params.artworkMinX = Float(paper.minX); params.artworkMinY = Float(paper.minY)
        params.artworkMaxX = Float(paper.maxX); params.artworkMaxY = Float(paper.maxY)
        memcpy(paramsBuf.contents(), &params, MemoryLayout<MetalFillEngine.FillParams>.size)
        if let params2Buf, let second = referenceColours.1 {
            var params2 = params
            params2.seedColor = second
            memcpy(params2Buf.contents(), &params2, MemoryLayout<MetalFillEngine.FillParams>.size)
        }

        let key = Structure.Key(seedX: seedX, seedY: seedY, seedColor: primary, threshold: threshold,
                                paper: boundary)
        let ceiling = FillBasins.ceiling(forGapWidth: max(gapWidth, gapWidthLimit))
        let structure: Structure
        if let kept = self.structure, kept.key == key, kept.ceiling >= ceiling {
            structure = kept
        } else {
            // The rebuild overwrites shared labels and feature buffers. A refusal cannot leave
            // the previous key pointing at those new or partially prepared contents.
            self.structure = nil
            completedMendCut = nil
            guard let built = buildStructure(key, ceiling: ceiling) else { return nil }
            self.structure = built
            structureBuilds += 1
            structure = built
        }
        let mends = Int(mendReach.rounded()) >= 1
        if mends {
            prepareVectorSupport()
            // Cut tables are already produced by the flood. Retaining a completed cut adds owned
            // CPU capacity; admit the new table arrays while the old key still exists.
            let outer = 2 * structure.passes.count * MemoryLayout<[UInt8]>.stride + 48
            let cutPrice = structure.passes.reduce(outer) { $0 + 2 * $1.basins.basinCount + 48 }
            if supportBuffers != nil && (cutPrice > MetalFillEngine.fillBudgetBytes - allocatedBytes
                || !CompositorBudget.hasHeadroom(for: cutPrice)) {
                vectorSupport = .unavailable
                completedMendCut = nil
            }
        }

        // The cut, then invert and erode (lasso) or edge-overlap dilate (bucket), paint, read back.
        guard let cb3 = engine.makeCommandBuffer() else { return nil }
        if let filledBuf, let blit = cb3.makeBlitCommandEncoder() {
            blit.fill(buffer: filledBuf, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
            blit.endEncoding()
        }
        guard let enc3 = cb3.makeComputeCommandEncoder() else { return nil }
        // The basin transform spent these coordinates as watershed scratch. Only mending needs
        // open features; prepare them on its first enabled tick, then retain them across off/on.
        // Availability is published after completion, so a failed command cannot cache partial data.
        let nearestOpen: MTLBuffer?
        if mends && supportBuffers != nil {
            if let kept = structure.nearestOpenFeatures {
                nearestOpen = kept
            } else {
                completedMendCut = nil
                encodeNearestOpenFeatures(enc3)
                nearestOpen = featureCoordinates
            }
        } else {
            nearestOpen = nil
        }
        // One table a pass, cut for this slider value, and the region rewritten from the labels — the
        // whole of a Gap Closing tick.
        var currentCut: [[UInt8]] = []
        if mends && supportBuffers != nil {
            currentCut.reserveCapacity(passes.count)
            if currentCut.capacity * MemoryLayout<[UInt8]>.stride
                > 2 * passes.count * MemoryLayout<[UInt8]>.stride + 16 {
                vectorSupport = .unavailable; completedMendCut = nil
            }
        }
        for (pass, gap) in zip(passes, structure.passes) {
            let table = gap.basins.reached(from: gap.seeds, gapWidth: gapWidth)
            if mends && supportBuffers != nil {
                if table.capacity <= 2 * table.count + 16 { currentCut.append(table) }
                else { vectorSupport = .unavailable; completedMendCut = nil; currentCut.removeAll() }
            }
            table.withUnsafeBytes { memcpy(gap.table.contents(), $0.baseAddress!, table.count) }
            engine.encode2D(enc3, p.basinRegion, width: width, height: height,
                            buffers: [(pass.labels, 0), (gap.table, 1), (pass.region, 2), (paramsBuf, 3)])
        }
        let needsMendSupport = mends && completedMendCut != currentCut
        var finished = false
        if needsMendSupport { completedMendCut = nil }
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
            engine.encode2D(enc3, p.lassoEdgeErode, width: width, height: height,
                            buffers: [(alphaBuf, 0), (lassoBuf, 1), (regionTmpBuf, 2), (paramsBuf, 3),
                                      (filledBuf, 4)])
            // **After the erosion and the count, not before**: the mend adds colour outside the fence
            // on purpose and must not change what the §6 step 5 empty check saw — a fill that was
            // eroded away is still an empty fill, whatever a neighbour would have lent it.
            if needsMendSupport {
                encodeMendSupport(enc3, source: alphaBuf, refCount: referenceColours.1 == nil ? 1 : 2, fence: lassoBuf)
            }
            if mends { encodeMend(enc3, painted: regionTmpBuf, source: alphaBuf, reach: mendReach,
                                            refCount: referenceColours.1 == nil ? 1 : 2,
                                            nearestOpen: nearestOpen ?? featureCoordinates, fence: lassoBuf) }
            engine.encode2D(enc3, p.paintAlpha, width: width, height: height,
                            buffers: [(regionTmpBuf, 0), (outBuf, 1), (paramsBuf, 2)])
        } else {
            // Into `regionTmpBuf` at every radius — 0 is a copy — so the mend never writes the cut.
            engine.encode2D(enc3, p.edgeDilate, width: width, height: height,
                            buffers: [(regionBuf, 0), (regionTmpBuf, 1), (paramsBuf, 2)])
            if needsMendSupport { encodeMendSupport(enc3, source: regionBuf, refCount: 1, fence: nil) }
            if mends { encodeMend(enc3, painted: regionTmpBuf, source: regionBuf, reach: mendReach,
                                            refCount: 1, nearestOpen: nearestOpen ?? featureCoordinates,
                                            fence: lassoBuf) }
            if mends {
                // **Ink the flood went round is filled under** (`FillEnclosedInk`): a CPU walk over the finished
                // region, so the region is settled first and the paint is encoded afterwards.
                enc3.endEncoding()
                cb3.commit()
                cb3.waitUntilCompleted()
                guard cb3.status == .completed else { return nil }
                referenceRGBA.withUnsafeBytes { reference in
                    let wall = hasPathWall ? UnsafeRawPointer(pathWallBuf.contents()) : nil
                    FillEnclosedInk.absorb(region: regionTmpBuf.contents().bindMemory(to: UInt8.self, capacity: count),
                                           reference: reference.baseAddress!, pathWall: wall, seed: primary,
                                           width: width, height: height)
                }
                guard let paintBuffer = engine.makeCommandBuffer(),
                      let paintEncoder = paintBuffer.makeComputeCommandEncoder() else { return nil }
                engine.encode2D(paintEncoder, p.paint, width: width, height: height,
                                buffers: [(regionTmpBuf, 0), (outBuf, 1), (paramsBuf, 2)])
                paintEncoder.endEncoding()
                paintBuffer.commit()
                paintBuffer.waitUntilCompleted()
                guard paintBuffer.status == .completed else { return nil }
                finished = true
            } else {
                engine.encode2D(enc3, p.paint, width: width, height: height,
                                buffers: [(regionTmpBuf, 0), (outBuf, 1), (paramsBuf, 2)])
            }
        }
        if !finished {
            enc3.endEncoding()
            cb3.commit()
            cb3.waitUntilCompleted()
            guard cb3.status == .completed else { return nil }
        }
        if let nearestOpen { self.structure?.nearestOpenFeatures = nearestOpen }
        if needsMendSupport { completedMendCut = currentCut }

        if let filledBuf {
            // `lassoEdgeErode`'s count, and nothing else's — one slot, one writer, and it runs on
            // every fill, so this is correct at every radius by construction.
            lastFilledPixelCount = Int(filledBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee)
        }
        var result = [UInt8](repeating: 0, count: count * 4)
        result.withUnsafeMutableBytes { memcpy($0.baseAddress!, outBuf.contents(), count * 4) }
        return result
    }

    // MARK: - What the slider cannot change

    /// The walls, the distance map's basins and the seeds they are reached from, and the inputs they
    /// were computed for. `fill` rebuilds it when the key moves, or when it is asked for a gap closing
    /// wider than the distance map was capped for.
    private struct Structure {
        struct Key: Equatable {
            var seedX: Int, seedY: Int
            var seedColor: SIMD4<Float>
            var threshold: Float
            var paper: CGRect?
        }
        let key: Key
        /// One per pass, in `passes`' order.
        let passes: [Basins]
        /// Nil until the first enabled mend finishes; shares the session's coordinate allocation.
        var nearestOpenFeatures: MTLBuffer?
        /// The level the distance map was capped at: every cut whose `FillBasins.ceiling` is no higher
        /// is exact on these basins.
        let ceiling: Int
    }

    /// One pass's basins, the basins its seeds lie in, and the table its cut is written to.
    private struct Basins {
        let basins: FillBasins
        let seeds: [Int32]
        let table: MTLBuffer
    }

    private var structure: Structure?

    /// Whether the current structure owns a completed nearest-open map. Derived from that owner,
    /// rather than a second validity flag, since the coordinate allocation is reused during rebuilds.
    var hasPreparedMendFeatures: Bool { structure?.nearestOpenFeatures != nil }

    /// How many times this session has built its `Structure` — once per press, and again only when
    /// the threshold, the paper or the seed moves. A slider tick that rebuilt would show here;
    /// `FillGapClosingLogicTests` reads it.
    private(set) var structureBuilds = 0

    /// The passes a fill runs, each with the params its walls are measured against, the walls, the
    /// region it writes (the domain while the basins are built, the cut after) and the labels its
    /// basins are written to. A bucket fill has one; a lasso has one per reference colour, because §6
    /// step 3 defines the reached set as the union of *per-colour* reachability rather than
    /// reachability through one merged passable set — a collar may not walk paper → flat → paper.
    private var passes: [(params: MTLBuffer, wall: MTLBuffer, region: MTLBuffer, labels: MTLBuffer)] {
        var passes = [(params: paramsBuf, wall: wallBuf, region: regionBuf, labels: labelsBuf)]
        if let params2Buf, let wall2Buf, let region2Buf, let labels2Buf, referenceColours.1 != nil {
            passes.append((params2Buf, wall2Buf, region2Buf, labels2Buf))
        }
        return passes
    }

    /// For each pass: the walls, the domain (`fillDomain`), the distance map capped at `ceiling`, and
    /// the basins `FillBasins` partitions the domain into — the flood and gap closing in one. The
    /// params buffers already hold `key`'s values.
    private func buildStructure(_ key: Structure.Key, ceiling: Int) -> Structure? {
        let p = engine.pipelines
        var built: [Basins] = []
        for pass in passes {
            guard let cb = engine.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return nil }
            engine.encode2D(enc, p.walls, width: width, height: height,
                            buffers: [(refBuf, 0), (pass.wall, 1), (pass.params, 2), (pathWallBuf, 3)])
            var hasLoop = UInt32(lassoBuf == nil ? 0 : 1)
            enc.setComputePipelineState(p.fillDomain)
            enc.setBuffer(pass.wall, offset: 0, index: 0)
            enc.setBuffer(lassoBuf ?? pass.wall, offset: 0, index: 1)
            enc.setBuffer(pass.region, offset: 0, index: 2)
            enc.setBuffer(paramsBuf, offset: 0, index: 3)
            enc.setBytes(&hasLoop, length: MemoryLayout<UInt32>.size, index: 4)
            engine.dispatch2D(enc, p.fillDomain, width: width, height: height)
            engine.encodeNearestFeatures(enc, width: width, height: height,
                                         wall: pass.wall, wall2: pass.wall, params: pass.params,
                                         refCount: 1, targetsInk: 1,
                                         workspace: featureWorkspace, result: featureCoordinates)
            let levels = featureWorkspace
            var canvasEdgeIsInk = UInt32(key.paper == nil ? 0 : 1)
            var cap = UInt32(ceiling)
            enc.setComputePipelineState(p.gapLevels)
            enc.setBuffer(featureCoordinates, offset: 0, index: 0)
            enc.setBuffer(levels, offset: 0, index: 1)
            enc.setBuffer(paramsBuf, offset: 0, index: 2)
            enc.setBytes(&canvasEdgeIsInk, length: MemoryLayout<UInt32>.size, index: 3)
            enc.setBytes(&cap, length: MemoryLayout<UInt32>.size, index: 4)
            engine.dispatch2D(enc, p.gapLevels, width: width, height: height)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            guard cb.status == .completed else { return nil }

            let labels = pass.labels.contents().bindMemory(to: Int32.self, capacity: count)
            // Exact feature coordinates are spent; the same buffer is watershed scratch.
            let basins = FillBasins(levels: levels.contents().bindMemory(to: UInt16.self, capacity: count),
                                    inDomain: pass.region.contents().bindMemory(to: UInt8.self, capacity: count),
                                    width: width, height: height, labels: labels,
                                    scratch: featureCoordinates.contents().bindMemory(to: Int32.self, capacity: 2 * count))
            let seeds: [Int32]
            if let ringBuf {
                // Every basin the ring touches: the collar starts from all of them.
                let ring = ringBuf.contents().bindMemory(to: UInt8.self, capacity: count)
                var touched = Set<Int32>()
                for i in 0..<count where ring[i] != 0 && labels[i] >= 0 { touched.insert(labels[i]) }
                seeds = Array(touched)
            } else {
                // A tap on a wall is in no basin, and reaches nothing.
                seeds = [labels[key.seedY * width + key.seedX]]
            }
            guard let table = engine.device.makeBuffer(length: max(4, basins.basinCount),
                                                       options: .storageModeShared) else { return nil }
            built.append(Basins(basins: basins, seeds: seeds, table: table))
        }
        return Structure(key: key, passes: built, nearestOpenFeatures: nil, ceiling: ceiling)
    }

    /// Which of `sides` the **last** `fill(...)` painted within `band` pixels of — the question
    /// `FillWindow` grows a bucket window on (TODO (86)). A flood that reaches the band may have more
    /// to reach past the buffer's rim, and a distance measured in the band was measured without the
    /// walls beyond it, so a window is trusted only where the paint keeps `band` clear of every edge
    /// that is not the canvas's own.
    ///
    /// Read on `fillQueue` after `fill` returned, so the shared buffer is settled — the same standing
    /// `lastReachedMask()` relies on.
    func paintedReaches(band: Int, of sides: FillWindow.Sides) -> FillWindow.Sides {
        let out = outBuf.contents().bindMemory(to: UInt8.self, capacity: count * 4)
        let band = max(1, min(band, width, height))
        func painted(in xs: Range<Int>, _ ys: Range<Int>) -> Bool {
            for y in ys { for x in xs where out[(y * width + x) * 4 + 3] != 0 { return true } }
            return false
        }
        var reached = FillWindow.Sides()
        if sides.contains(.left), painted(in: 0..<band, 0..<height) { reached.insert(.left) }
        if sides.contains(.right), painted(in: (width - band)..<width, 0..<height) { reached.insert(.right) }
        if sides.contains(.top), painted(in: 0..<width, 0..<band) { reached.insert(.top) }
        if sides.contains(.bottom), painted(in: 0..<width, (height - band)..<height) { reached.insert(.bottom) }
        return reached
    }

    // MARK: - The mend

    private func encodeNearestOpenFeatures(_ enc: MTLComputeCommandEncoder) {
        engine.encodeNearestFeatures(enc, width: width, height: height,
                                     wall: wallBuf, wall2: wall2Buf ?? wallBuf, params: paramsBuf,
                                     refCount: referenceColours.1 == nil ? 1 : 2,
                                     targetsInk: 0,
                                     workspace: featureWorkspace, result: featureCoordinates)
    }

    /// Grows `painted` (a flag buffer or a coverage buffer, in place) into the ink between it and the
    /// neighbour set — `mendGap` in Fill.metal. `reach` is in working pixels.
    ///
    /// The kernel writes to a buffer of its own and `unionMask` folds it in, because every pixel's walk
    /// reads `painted` at its neighbours. The scratch is the feature transform's first buffer, which is free by now:
    /// the distance-map/watershed workspace is spent once basins are built. Its first N bytes hold
    /// this mask; its aligned upper4N bytes retain the source-owned known/protected stencil.
    private func encodeMend(_ enc: MTLComputeCommandEncoder, painted: MTLBuffer, source: MTLBuffer,
                            reach: Float, refCount: UInt32, nearestOpen: MTLBuffer,
                            fence: MTLBuffer? = nil, mergeIntoPainted: Bool = true) {
        let p = engine.pipelines
        var reachPixels = reach
        // Keep the open-to-open proof separate from the uncovered-gap Reach. The supported bucket
        // overlap can cover both sides of a strip. This finite geometric cap is not historical
        // provenance for an arbitrarily edited saved fill; unresolved wider geometry stays alone.
        var proofSpan = reach + 2 * Float(CanvasManager.fillExpandRange.upperBound)
        var references = refCount
        var hasFence = UInt32(fence == nil ? 0 : 1)
        enc.setComputePipelineState(p.mendGap)
        enc.setBuffer(painted, offset: 0, index: 0)
        enc.setBuffer(source, offset: 0, index: 1)
        enc.setBuffer(neighbourBuf, offset: 0, index: 2)
        enc.setBuffer(wallBuf, offset: 0, index: 3)
        enc.setBuffer(wall2Buf ?? wallBuf, offset: 0, index: 4)
        enc.setBuffer(nearestOpen, offset: 0, index: 5)
        enc.setBuffer(featureWorkspace, offset: 0, index: 6)
        enc.setBuffer(paramsBuf, offset: 0, index: 7)
        enc.setBytes(&reachPixels, length: MemoryLayout<Float>.size, index: 8)
        enc.setBytes(&references, length: MemoryLayout<UInt32>.size, index: 9)
        enc.setBuffer(fence ?? wallBuf, offset: 0, index: 10)
        enc.setBytes(&hasFence, length: MemoryLayout<UInt32>.size, index: 11)
        enc.setBytes(&proofSpan, length: MemoryLayout<Float>.size, index: 12)
        engine.dispatch2D(enc, p.mendGap, width: width, height: height)
        if mergeIntoPainted {
            engine.encode2D(enc, p.unionMask, width: width, height: height,
                            buffers: [(featureWorkspace, 0), (painted, 1), (paramsBuf, 2)])
        }
    }
}

// MARK: - Ink the fill is enclosed around

/// **Ink the flood went round, and the pinholes between its speckle** — what a bucket fill with Mend Gaps on
/// adds to the region once the flood, the Edge Overlap and the mend have run (the owner's November 17 ruling:
/// *a line drawn inside the shape is filled under, whole, with no hairline*).
///
/// The flood stops at ink, so a line inside a circle leaves the line itself bare. The rule is topological
/// rather than a width or a reach. **Solid** is any pixel the region does not hold that is ink — differs from
/// the tapped colour at all, so a rough or antialiased fringe belongs to it — or is an unfilled pocket of at
/// most `pinholeLimit` pixels not touching the window's edge (what a rough brush's speckle leaves between its
/// dabs). A connected piece of solid (8-connected) is **enclosed** when every pixel around it is already in the
/// region: it touches no unfilled open paper and not the window's edge. An enclosed piece is added. A piece that
/// touches unfilled paper is left to Edge Overlap and the mend: the circle's own outline (paper outside it), and
/// a ring around a hole (its inside is open paper the region did not reach, so the ring is a boundary, not an
/// island).
///
/// One pass over the window plus a walk of each piece: O(window pixels), with no GPU round trip of its own.
enum FillEnclosedInk {
    /// The largest unfilled pocket, in pixels, that counts as part of the ink round it.
    static let pinholeLimit = 16
    /// How far a channel may differ from the tapped colour before a pixel counts as ink, in 8-bit steps.
    static let inkTolerance = 2

    private enum Kind {
        static let open: UInt8 = 0       // unfilled paper, not yet judged
        static let solid: UInt8 = 1      // ink, or a pocket small enough to be part of it
        static let filled: UInt8 = 2     // in the region
        static let wide: UInt8 = 3       // unfilled paper in a pocket too big, or at the window's edge
        static let queued: UInt8 = 4     // in the pocket walk being made
        static let visited: UInt8 = 5    // a solid pixel already assigned to a piece
    }

    /// - Parameters:
    ///   - region: one byte a pixel, non-zero where the fill is; extended in place.
    ///   - reference: the working window's RGBA reference (premultiplied), `width * height * 4` bytes.
    ///   - pathWall: the vector layers' stroke centre lines, in the reference's layout, or nil — a pixel with
    ///     alpha there is ink whatever the reference shows, so a segmented brush's dots join up.
    ///   - seed: the tapped colour, premultiplied 0...1.
    /// - Returns: how many pixels were added.
    @discardableResult
    static func absorb(region: UnsafeMutablePointer<UInt8>, reference: UnsafeRawPointer,
                       pathWall: UnsafeRawPointer?, seed: SIMD4<Float>, width: Int, height: Int) -> Int {
        let count = width * height
        guard count > 0 else { return 0 }
        let seedBytes = (0..<4).map { Int(max(0, min(255, (seed[$0] * 255).rounded()))) }
        let seedWord = UInt32(seedBytes[0]) | UInt32(seedBytes[1]) << 8
            | UInt32(seedBytes[2]) << 16 | UInt32(seedBytes[3]) << 24
        let tolerance = inkTolerance
        let around = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        var kind = [UInt8](repeating: Kind.open, count: count)
        var members: [Int32] = []
        var added = 0

        kind.withUnsafeMutableBufferPointer { kind in
            // 1. Classify: the region, ink, and the rest.
            for i in 0..<count {
                if region[i] != 0 { kind[i] = Kind.filled; continue }
                if let pathWall, pathWall.load(fromByteOffset: i * 4 + 3, as: UInt8.self) != 0 {
                    kind[i] = Kind.solid; continue
                }
                if reference.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self) == seedWord { continue }
                for c in 0..<4 where abs(Int(reference.load(fromByteOffset: i * 4 + c, as: UInt8.self)) - seedBytes[c]) > tolerance {
                    kind[i] = Kind.solid; break
                }
            }

            // 2. Unfilled pockets small enough to be ink's own speckle. A pocket is only ever beside something that
            //    is not open paper, so the walk starts there; a pocket past the limit — or at the window's edge —
            //    is marked wide as far as it was walked, which keeps every pixel to one walk.
            for beside in 0..<count where kind[beside] == Kind.solid || kind[beside] == Kind.filled {
              let bx = beside % width, by = beside / width
              for (sdx, sdy) in around {
                let sx = bx + sdx, sy = by + sdy
                guard sx >= 0, sy >= 0, sx < width, sy < height, kind[sy * width + sx] == Kind.open else { continue }
                let start = sy * width + sx
                members.removeAll(keepingCapacity: true)
                members.append(Int32(start)); kind[start] = Kind.queued
                var wide = false, head = 0
                walk: while head < members.count {
                    let p = Int(members[head]); head += 1
                    let x = p % width, y = p / width
                    for (dx, dy) in around {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { wide = true; break walk }
                        let q = ny * width + nx
                        switch kind[q] {
                        case Kind.wide: wide = true; break walk
                        case Kind.open:
                            kind[q] = Kind.queued; members.append(Int32(q))
                            if members.count > pinholeLimit { wide = true; break walk }
                        default: break
                        }
                    }
                }
                let result = wide ? Kind.wide : Kind.solid
                for m in members { kind[Int(m)] = result }
              }
            }

            // 3. Each connected piece of solid, added when everything round it is in the region.
            for start in 0..<count where kind[start] == Kind.solid {
                members.removeAll(keepingCapacity: true)
                members.append(Int32(start)); kind[start] = Kind.visited
                var enclosed = true, head = 0
                while head < members.count {
                    let p = Int(members[head]); head += 1
                    let x = p % width, y = p / width
                    for (dx, dy) in around {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { enclosed = false; continue }
                        let q = ny * width + nx
                        switch kind[q] {
                        case Kind.solid: kind[q] = Kind.visited; members.append(Int32(q))
                        case Kind.open, Kind.wide: enclosed = false
                        default: break
                        }
                    }
                }
                if enclosed {
                    for m in members { region[Int(m)] = 1 }
                    added += members.count
                }
            }
        }
        return added
    }
}
