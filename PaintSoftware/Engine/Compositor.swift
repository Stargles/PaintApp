import UIKit
import os

// MARK: - The compositor
//
// One headless entry point that turns a `RenderRequest` into a frame. LAYER_COMPOSITING.md §1: the
// app has two unrelated compositing implementations that already disagree, and adding masks and
// blends to both guarantees drift — so build one, and delete the other (§5.2, phase 3).
//
// Two backends, one contract. The Core Graphics one is the reference: it is what `composite` falls
// back to when there is no GPU, it is the only one the fast test tier can run (see
// `CompositorBackend`), and it is the byte-for-byte definition of correct that the Metal one is
// measured against. §11's phase 2 gate — "byte-identical to the Core Animation path for all-normal,
// no-mask documents" — is enforced against it.

/// Which implementation `Compositor.composite` uses.
///
/// **Defaults to `.automatic`, and the two sentences that used to be here are both withdrawn.** The
/// first said the flag would flip when a consumer needed the GPU at interactive rates; the second,
/// written when it did flip, said "the *sign* is what the flip rests on, and it is the same sign in
/// all three rows". Both were argued from simulator numbers, and **the sign is not the same on the
/// device.** A blanket `.metal` is the wrong shape of answer: which backend wins is a property of
/// the document, so the default is now a predicate over the tree
/// (`[RenderNode].prefersGPUCompositing`, which carries the rule and the numbers behind it).
///
/// **Measured on the owner's iPad 9 (`iPad12,1`, A13, 3 GB), Release, 2048², both backends warm.**
/// These supersede the simulator table that stood here; the simulator's figures are not quoted any
/// more because two of the three ratios it reported do not survive contact with the hardware.
///
/// | | CoreGraphics | Metal |
/// |---|---|---|
/// | per-layer slope (`testWhereAWarmCompositeSpendsItself`) | 4.3 ms | **2.4 ms** |
/// | fixed intercept, per composite | **4.2 ms** | 7.0 ms |
/// | one-pass grade, added cost (`testEffectCompositeCostOnBothBackends`) | 203.3 ms | **2.7 ms** |
/// | peak footprint, 6 plain layers | **381.3 MB** | 461.7 MB |
/// | sandwich rebuild, 6 layers, warm | 64.7 ms | **54.8 ms** |
/// | the same, cold | **64.7 ms** | 108.1 ms |
///
/// **Metal is half the document and twice the frame**, so the two lines cross at about one and a half
/// leaves — and a naive reading of that alone is exactly how the blanket default got written. The
/// footprint row is why that reading is wrong: the GPU path holds a canvas-sized pool and upload
/// cache the CPU path never allocates, +80 MB here, on the device whose scarcity of that resource is
/// what crashed the app in the first place. At two leaves Metal is buying about a millisecond with
/// it. So the threshold sits deliberately above the timing crossover.
///
/// **The grade row is the one that is not close and never was.** 203.3 ms against 2.7 ms, on the
/// smallest stack that can carry an effect: `CoreGraphicsCompositor.grade` snapshots the canvas,
/// grades 4.2M pixels in Swift and writes a third buffer (slow on purpose — it is the oracle), while
/// the GPU adds one dispatch over a texture that is already resident. Seventy-five to one is not a
/// tuning difference, and it is the shape every §4.4 document has. That is the clause doing the real
/// work in the predicate.
///
/// **The cold row is still true and still matters for one consumer.** With nothing cached the GPU
/// pays every upload — 108.1 ms against 64.7 — so its win is "every frame after the first". The
/// offline consumer that is always cold is the project thumbnail (`ProjectStore`), which composites
/// once per save and is not on any interactive path.
///
/// **None of this is what makes a 4K canvas safe on 3 GB — `CompositorBudget` is.** The predicate
/// picks a backend; the budget decides whether the picked one can afford the frame, and sizes the
/// live canvas so it can. They are separate questions and the code keeps them separate.
///
/// **The fast tier can select either, which is new.** The `PaintSoftwareUITests` target opts out of
/// the app's `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so it had no shader of
/// any kind and `device.makeDefaultLibrary()` returned nil there — the reason `MetalFillEngine` has
/// never been exercisable outside a real app process. `Composite.metal` is an explicit member of that
/// target and `CompositorMetalEngine` asks for its library by `Bundle(for:)` rather than
/// `Bundle.main`, so both backends run headlessly and `CompositorParityLogicTests` compares them
/// directly. `Fill.metal` is still not a member, so `MetalFillEngine.shared` remains nil there.
enum CompositorBackend {
    case coreGraphics
    case metal
    /// **Decided per composite from the tree** — `[RenderNode].prefersGPUCompositing`, which carries
    /// the device measurements it is chosen from. The shipped default, and the correction to a
    /// blanket `.metal` that the iPad's own numbers forced.
    case automatic
}

// MARK: - What the GPU path may spend

/// **How much canvas-sized texture the GPU compositor is allowed to hold, on the device it is
/// actually running on.**
///
/// ### Why this exists: every number the backend flip rests on was measured on a Mac
///
/// The simulator borrows a desktop's memory and a desktop's GPU, so a working set that disappears
/// there is the whole budget on an iPad. The owner's report is the measurement that was missing —
/// a 4096² canvas, one vector layer, two value layers carrying bloom and blur, on an **iPad 9th
/// generation (`iPad12,1`, A13, 3 GB shared between CPU and GPU)** — and the arithmetic for that
/// exact scene is:
///
/// | | textures | each | total |
/// |---|---|---|---|
/// | root accumulator pair (`front`/`back`) | 2 | 64 MiB | 128 MiB |
/// | effect scratch for a grading leaf | 1 | 64 MiB | 64 MiB |
/// | `EffectPipelines` intermediates (bloom is four passes) | 2 | 64 MiB | 128 MiB |
/// | upload cache, the one leaf that has pixels | 1 | 64 MiB | 64 MiB |
/// | **held simultaneously** | **6** | | **384 MiB** |
///
/// — and that is only the textures. The same rebuild also holds three readback `CGImage`s (192 MiB,
/// one per sandwich half), the two Core Animation surfaces the sandwich views convert them into
/// (128 MiB), and a canvas-sized staging buffer per upload. Roughly 700 MiB of live allocation for
/// one repaint, on a device where the whole app has perhaps 1.4 GB before jetsam and the document's
/// own raster tiers already want several hundred. `Metal.makeTexture` is not the thing that fails
/// there — jetsam kills the process before it returns nil, which is why a nil check at the
/// allocation site was never going to catch this.
///
/// `PerfBaselineTests.testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold` is that table,
/// asserted rather than recited.
///
/// **The upload cache's 192 MB cap was not the problem, and that is worth stating because it was the
/// obvious suspect.** Two of the three layers in that scene are grading layers, which hold no pixels
/// at all (`leafSnapshots` elides them), so the cache holds exactly one entry and hits every time.
/// The 320 MiB that is *not* the cache — the pool and the effect intermediates — had no budget of any
/// kind. That is what this type gives it.
///
/// ### The rule, and why it is this rule
///
/// Two questions, deliberately answered by two different mechanisms:
///
/// - **`textureBudgetBytes` is static for the process and derived from the device's total memory.**
///   It has to be static because two callers must agree about it: `makeSandwichRecipe` picks a
///   composite size on the main thread and `CompositorMetalEngine` decides whether to accept that
///   size on a background queue a moment later. A budget derived from free memory would let the
///   second answer differ from the first, and the sandwich would ask for a size the engine then
///   refuses — a silent whole-frame drop to a CPU path that at 4K with a bloom on it is not a frame
///   at all (see `affordableSize` for the arithmetic).
/// - **`hasHeadroom(for:)` is dynamic and reads `os_proc_available_memory()`.** That is the number
///   jetsam actually acts on, and it moves for reasons this app does not control: another app coming
///   to the foreground takes memory away without the canvas changing at all. So it is a *valve*, not
///   a budget — it can decline a composite the budget has already sized, and that decline is the one
///   `Compositor.composite` answers with nil rather than with the CPU reference, because the
///   reference would allocate *more* at the moment there is none. The canvas keeps the picture it
///   has, which is at most one edit stale, and the next rebuild retries.
///
/// `physicalMemory / 16` is 192 MiB on that 3 GB iPad and 512 MiB on an 8 GB iPad Pro. The divisor is
/// chosen from the ratio above rather than picked: the textures are roughly half of what a repaint
/// holds at its peak (six textures against three readback images, two CA surfaces and a staging
/// buffer), so a texture budget of one sixteenth of the device is a compositor peak of about one
/// eighth of it — which leaves the artist's document, the undo history and UIKit the other seven
/// eighths. A fraction of *free* memory would have been the tempting alternative and is wrong for
/// the reason above, plus one more: the pool and the cache are held between frames, so sizing them
/// by what happens to be free at the moment they are first filled writes a high-water mark that
/// nothing later lowers.
enum CompositorBudget {

    /// One canvas-sized `rgba8Unorm` texture at `size`, in bytes. Four bytes per pixel is the app's
    /// pixel contract everywhere (`PixelOps`), not a property of any one buffer.
    static func textureBytes(for size: CGSize) -> Int {
        let width = max(0, Int(size.width.rounded())), height = max(0, Int(size.height.rounded()))
        return width * height * 4
    }

    /// The ceiling on everything `CompositorMetalEngine` holds at once — the scratch pool, the
    /// multi-pass effect intermediates, and the upload cache together.
    static var textureBudgetBytes: Int {
        budgetOverrideBytes ?? textureBudgetBytes(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    /// The rule itself, given the memory a device reports — **a function of its argument so a test can
    /// ask what an iPad 9 would do while running on a Mac**, which is exactly the gap that let this
    /// ship. `textureBudgetBytes` is the same rule applied to the machine it is running on.
    ///
    /// Clamped at both ends. The 64 MiB floor keeps a device that reports an implausibly small
    /// `physicalMemory` from disabling the GPU path outright; the 768 MiB cap keeps a 16 GB iPad Pro
    /// from deciding that a gigabyte of resident texture is a reasonable thing for a paint program to
    /// sit on while the artist is in another app.
    static func textureBudgetBytes(physicalMemory: UInt64) -> Int {
        let physical = Int(clamping: physicalMemory)
        return min(max(physical / 16, 64 * 1024 * 1024), 768 * 1024 * 1024)
    }

    /// A budget imposed by a test, or nil for the device's own.
    ///
    /// **A development seam of exactly the kind `Compositor.backend` is**, and here for the same
    /// reason: the thing under test is a decision about a device that no test host is. Without it the
    /// only way to exercise the refusal is to run on the iPad that crashes, which is the loop this
    /// whole fix exists to get out of. Tests restore it to nil in `tearDown`.
    ///
    /// **Locked, because it is written on the test's thread and read from a compositing queue**
    /// (RENDER.md §4). `textureBudgetBytes` reads it on whichever queue
    /// `CompositorMetalEngine.attempt` is running on, and a test that arms it while a save's
    /// thumbnail composite is in flight was a plain unsynchronised `Int?` away from undefined
    /// behaviour. A lock rather than a snapshot into `RenderRequest`: this is the one of the four
    /// statics in that audit item that is *not* a property of the picture — it stands in for the
    /// device, and a request built before a test armed it must still see the armed value.
    static var budgetOverrideBytes: Int? {
        get {
            overrideLock.lock()
            defer { overrideLock.unlock() }
            return storedBudgetOverrideBytes
        }
        set {
            overrideLock.lock()
            defer { overrideLock.unlock() }
            storedBudgetOverrideBytes = newValue
        }
    }

    private static let overrideLock = NSLock()
    private static var storedBudgetOverrideBytes: Int?

    /// Whether the process can afford `bytes` of new allocation *right now*.
    ///
    /// `os_proc_available_memory()` is how many bytes remain before this process hits the limit
    /// jetsam kills it at. It returns 0 where the concept does not apply — the simulator, and any
    /// non-app process, which includes the fast test tier — and 0 is read as "no information" rather
    /// than as "no memory", so this is inert everywhere it cannot be trusted. That is deliberate: a
    /// valve that closed on the simulator would make every logic-tier composite take the CPU path and
    /// the parity tests would stop testing the GPU.
    ///
    /// **Twice `bytes`, because the textures are not the whole cost of the frame they belong to.**
    /// A composite that allocates `bytes` of texture then reads a canvas-sized image back out of it,
    /// hands that to the view layer, and Core Animation copies it again — none of which is freed
    /// before the next composite starts. Asking for exactly what the textures cost would let a frame
    /// begin that cannot finish.
    static func hasHeadroom(for bytes: Int) -> Bool {
        let available = os_proc_available_memory()
        guard available > 0 else { return true }
        return available > bytes * 2
    }

    /// The largest size no bigger than `size`, in the same aspect ratio, at which `textures`
    /// canvas-sized textures fit `textureBudgetBytes`.
    ///
    /// **This is the lever that keeps the GPU path on a device that cannot hold a 4K composite**, and
    /// it is a better trade than the two alternatives.
    ///
    /// Falling back to CoreGraphics is not "slower", it is a different order of thing. The measured
    /// point is a *single-pass* grade over 4.2M pixels: 7047 ms on the CPU reference against Metal's
    /// 18.8 ms (`PerfBaselineTests.testEffectCompositeCostOnBothBackends`, Debug). The owner's scene
    /// is 4x the pixels and, at radius 12, roughly fifty times the per-pixel work — bloom is four
    /// passes and two of them gather 25 samples each. Release is faster than Debug by a factor
    /// nobody here has measured for this path, and it does not need measuring: two orders of
    /// magnitude above seven seconds is not a frame, whatever the constant is.
    ///
    /// Refusing to composite at all loses the picture. Compositing fewer pixels loses *sharpness*, on
    /// an image the artist is already told is a preview (`RenderResolution`), and it is the only one
    /// of the three the artist can look at.
    ///
    /// Returns `size` unchanged when it already fits, which is every canvas the branch was measured
    /// on and every canvas on a device with room — so this is inert exactly where there was no
    /// problem.
    static func affordableSize(for size: CGSize, textures: Int) -> CGSize {
        affordableSize(for: size, textures: textures, budgetBytes: textureBudgetBytes)
    }

    /// `affordableSize(for:textures:)` against a stated budget rather than the running device's — the
    /// half a test can pin, for `textureBudgetBytes(physicalMemory:)`'s reason.
    static func affordableSize(for size: CGSize, textures: Int, budgetBytes budget: Int) -> CGSize {
        guard textures > 0, size.width > 0, size.height > 0 else { return size }
        let wanted = textureBytes(for: size) * textures
        guard wanted > budget else { return size }
        // Area scales as the square, so the linear scale is the square root of the byte ratio. Floored
        // to whole pixels for `RenderResolution.renderSize`'s reason — the backends and
        // `PixelOps.rasterize` do not round in the same place, and a source one pixel wider than the
        // composite reading it is a garbage frame on the GPU rather than a soft one.
        let scale = (Double(budget) / Double(wanted)).squareRoot()
        return CGSize(width: max(1, (size.width * scale).rounded(.down)),
                      height: max(1, (size.height * scale).rounded(.down)))
    }
}

/// Counts composites, and the size each was asked for — the instrument behind "how many of these did
/// that pass actually do", which is the question two performance claims turn on and neither could
/// answer before 2026-08-20.
///
/// **A count rather than a timing, deliberately.** A rebuild that composites three pictures where one
/// is looked at, or a thumbnail that composites two million pixels to fill fifty thousand, is wrong
/// by a *number* — and a number is stable under a loaded machine, which a millisecond on this Mac
/// provably is not (CLAUDE.md records five concurrent runs returning wrong answers, not merely slow
/// ones). So the assertions these serve are integers and sizes, and they need no device.
///
/// **Off by default and nearly free when off.** Armed only from a test, and the hook a shipped build
/// pays is one relaxed `Bool` load before a branch that is never taken — the same shape and the same
/// reasoning as `ActionRecorder`'s event tap, which is documented as costing exactly that. The lock
/// is taken only while armed, which matters because `composite` runs on `sandwichQueue` and on the
/// main actor both, sometimes in the same rebuild.
enum CompositeProbe {

    private static let lock = NSLock()
    /// Read outside the lock on the hot path. A stale read is harmless in both directions: the probe
    /// is armed before the code under test runs and read after it finishes, so there is no window in
    /// which a missed or extra observation could change an assertion.
    private static var isArmed = false
    private static var sizes: [CGSize] = []

    /// Starts recording, discarding anything held from a previous run.
    static func begin() {
        lock.lock(); defer { lock.unlock() }
        sizes = []
        isArmed = true
    }

    /// Stops recording and returns what was seen, in call order.
    @discardableResult
    static func end() -> [CGSize] {
        lock.lock(); defer { lock.unlock() }
        isArmed = false
        let seen = sizes
        sizes = []
        return seen
    }

    /// Everything composited since `begin()`, without stopping. For a test that wants to look
    /// part-way through a sequence.
    static func observed() -> [CGSize] {
        lock.lock(); defer { lock.unlock() }
        return sizes
    }

    fileprivate static func record(_ size: CGSize) {
        guard isArmed else { return }
        lock.lock(); defer { lock.unlock() }
        guard isArmed else { return }
        sizes.append(size)
    }
}

enum Compositor {

    /// The active backend. A `static var` rather than a `UserDefaults`-backed setting because this is
    /// a development seam, not something a user chooses — `CanvasManager.pencilOnlyDrawing` is what a
    /// real persisted preference looks like in this codebase, and this is deliberately not that.
    ///
    /// It stays a development seam now that the default has moved, and more so rather than less: the
    /// only thing it selects between is a fast implementation and the slow one it is measured against,
    /// and an artist has no way to tell them apart except by waiting. The user-facing performance knob
    /// added alongside this is render resolution, which changes the *picture* and is therefore a
    /// choice somebody can actually make.
    /// **Locked, because it is written on main and read from every compositing queue** (RENDER.md
    /// §4). `composite` switches on it from `CanvasView.sandwichQueue`
    /// and from `ProjectStore`'s save queue, while the fifty test sites that arm it do so from the
    /// test thread.
    ///
    /// **A lock and not a field on `RenderRequest`, which is what RENDER §3.3 asks for and is wrong
    /// here.** §3.3 wants the backend in the *bake key*, so a stored frame records which
    /// implementation drew it — that is a property of a finished picture. This is the seam that
    /// *chooses* the implementation, and every measurement in the project composites one already-built
    /// request through both backends in turn (`PerfBaselineTests`' CPU-versus-GPU pairs,
    /// `CompositorParityLogicTests`' sweeps). Snapshotting the choice at request-build time would make
    /// that impossible to express, and the parity suite is the only reason two backends still exist.
    /// The bake key will read this accessor when it is built.
    static var backend: CompositorBackend {
        get {
            backendLock.lock()
            defer { backendLock.unlock() }
            return storedBackend
        }
        set {
            backendLock.lock()
            defer { backendLock.unlock() }
            storedBackend = newValue
        }
    }

    private static let backendLock = NSLock()
    private static var storedBackend: CompositorBackend = defaultBackend

    /// What `backend` is in a process nobody has reconfigured — **the value a test's `tearDown`
    /// restores, and the reason it is a named constant rather than a literal repeated in five files.**
    ///
    /// Four suites already set `.coreGraphics` in `setUp` (they want the reference implementation) and
    /// wrote `.coreGraphics` back in `tearDown`, which was a correct restore for exactly as long as
    /// that was also the default. The moment it stopped being one, those `tearDown`s became a way for
    /// one suite to switch every suite that runs after it in the same process off the shipped backend
    /// — silently, since the tests would go on passing against the slower path they were not written
    /// to be measuring. Restoring *this* is what cannot rot.
    ///
    /// **`.automatic` rather than `.metal`, and the two forced cases stay for the tests and the
    /// measurements.** A parity sweep has to name the backend it is comparing — it cannot be handed
    /// a document-dependent answer — and every case in `PerfBaselineTests` that reports a
    /// CPU-versus-GPU pair has to force both sides. So the enum keeps three cases where the app only
    /// ever ships one: two of them exist so the third can be measured.
    static let defaultBackend: CompositorBackend = .automatic

    /// Composites one frame. Pure: every input is a value the caller owns, so this is safe to call
    /// from any thread — which is the whole point of §9.1 point 3 and what makes §9.2's background
    /// renderer a thread rather than a rewrite.
    ///
    /// Returns nil for a degenerate canvas size, **and now for one more case**: a GPU composite
    /// declined because the process is out of memory right now. See below.
    static func composite(_ request: RenderRequest) -> CGImage? {
        composite(request, resolving: backend)
    }

    /// **`.automatic` resolved by the caller instead of by this request** — the one-frame-one-backend
    /// rule RENDER.md §3.4's chunking needs.
    ///
    /// `.automatic` is a predicate over `request.tree` (`prefersGPUCompositing`), and a chunk's tree is
    /// not the frame's: a hundred-leaf document resolves to Metal, while chunk after chunk of two
    /// leaves apiece resolves to CoreGraphics. The two backends agree exactly for source-over and to
    /// within a channel step for the blend modes, so a frame that switched between them mid-walk would
    /// be a frame whose bytes depend on where the chunk boundaries fell — and §5 stage 3's pin is
    /// byte-for-byte. So `ChunkedCompositor` asks the *whole* tree once and hands the answer to every
    /// chunk.
    ///
    /// **This does not make a frame single-backend, and that is worth saying plainly.** A `.metal`
    /// chunk that comes back `.unavailable` — no GPU, no metallib, a failed encode — still falls back
    /// to CoreGraphics for that chunk alone, exactly as it always has. What is removed is the
    /// *systematic* mixing that `.automatic` would do on tree size; what remains is the same
    /// per-composite fallback the app has always had, and it fires for reasons that are properties of
    /// the device rather than of the chunk boundary.
    static func composite(_ request: RenderRequest, resolving choice: CompositorBackend) -> CGImage? {
        CompositeProbe.record(request.canvasSize)
        switch choice {
        case .coreGraphics:
            return CoreGraphicsCompositor.composite(request)
        // **The shipped path, and it asks the tree rather than a constant.** See
        // `[RenderNode].prefersGPUCompositing` for the iPad 9 measurements that decide it — the short
        // version is that Metal is half the per-layer cost and twice the per-frame cost, so which one
        // wins is a property of the document, and a grade anywhere makes it Metal by seventy-five to
        // one whatever else is in the stack.
        case .automatic:
            guard request.tree.prefersGPUCompositing else {
                return CoreGraphicsCompositor.composite(request)
            }
            return compositeThroughMetal(request)
        case .metal:
            return compositeThroughMetal(request)
        }
    }

    /// The GPU attempt and the two shapes of "no" it can come back with — factored out because both
    /// `.metal` and `.automatic` reach it, and the fallback rule is the interesting part rather than
    /// the dispatch.
    private static func compositeThroughMetal(_ request: RenderRequest) -> CGImage? {
        switch MetalCompositor.attempt(request) {
        case .image(let image):
            return image
        // Falling back rather than failing: a device with no GPU, or the fast test tier with no
        // metallib, should render a correct frame slowly rather than no frame at all. The two
        // backends agree exactly for source-over and to within a channel step for the blend
        // modes (`CompositorParityLogicTests` measures every one), so this is a performance
        // fallback and never a visual one.
        case .unavailable:
            return CoreGraphicsCompositor.composite(request)
        // **The one decline that must not escalate, and the reason this stopped being one
        // branch.** The fallback above is whole-frame — a single failed encode drops the entire
        // composite to the CPU — which is the right trade when the GPU is *absent*. It is exactly
        // the wrong one when the GPU declined for lack of memory: `CoreGraphicsCompositor.grade`
        // reads the canvas back, allocates a second canvas-sized buffer for the graded copy and a
        // third for the result, and gathers a whole blur kernel per pixel in scalar Swift. So the
        // response to "there is no memory" would be to allocate more of it, far more slowly, at
        // the moment jetsam is deciding whether to kill the process.
        //
        // Nil is a better answer here than either backend, because the caller already has one.
        // `CanvasView.finishSandwichRebuild` takes all three composites or none and otherwise
        // keeps showing what it has, which is at most one edit stale and is a coherent picture;
        // the next rebuild retries, by which time the purge this decline triggered has given the
        // memory back. `ProjectStore` writes no thumbnail for that save, which is a tile the next
        // save replaces.
        case .underPressure:
            return nil
        }
    }
}

// MARK: - Blend modes on the CPU

extension BlendMode {

    /// The `CGBlendMode` that computes this mode, or **nil when CoreGraphics has no equivalent** and
    /// `CoreGraphicsCompositor` has to compute it per pixel itself.
    ///
    /// Eleven of the fourteen Tier 1 modes are CoreGraphics primitives, and that is worth leaning on
    /// rather than hand-rolling for uniformity: `CGBlendMode` implements the PDF imaging model's
    /// separable blend functions, which are the same formulas `Composite.metal` implements from the
    /// W3C spelling of them. So the CPU reference is *Apple's* implementation of the blend, not a
    /// second copy of the shader's — which is what makes the GPU-versus-CPU delta a real measurement
    /// instead of a test of whether one author wrote the same expression twice.
    ///
    /// **The three Tier 1 hand-rolled modes (`add`, `subtract`, `linearLight`) are hand-rolled because
    /// they are absent, not because they are awkward.** CoreGraphics offers `.plusLighter`, which
    /// looks like Add and is not: it is Porter-Duff *plus*, summing premultiplied channels including
    /// alpha, so it agrees with linear dodge only where the backdrop is opaque and the sum does not
    /// clamp, and it inflates alpha everywhere else. Substituting it would be wrong in exactly the
    /// cases a blend mode is interesting.
    ///
    /// **Tier 2 was swept the same way, and only one of its five Apple-backed modes actually keeps the
    /// primitive.** `vividLight`, `pinLight`, `linearBurn`, `divide`, `lighterColor` and `darkerColor`
    /// have no `CGBlendMode` case at all — absent, the `add`/`subtract`/`linearLight` category.
    /// `exclusion`, `hue`, `saturation`, `color` and `luminosity` *do* have Apple cases, but the switch
    /// below only returns one of them: `.exclusion` keeps `.exclusion`, while `.hue`, `.saturation`,
    /// `.color` and `.luminosity` return `nil` unconditionally, so `handRolledTriple` is the live path
    /// for all four, not a fallback.
    ///
    /// That split is a choice, not a measured disagreement. `exclusion`'s delta of 0
    /// (`CompositorParityLogicTests.testEveryBlendModeAgreesBetweenTheBackends`) is a genuine
    /// CoreGraphics-versus-spec data point, the same kind `multiply`'s delta of 1 is. The other four's
    /// reported deltas (hue 1, saturation 0, color 1, luminosity 1) are not: since this backend already
    /// hand-rolls those four, that sweep compares the GPU shader's W3C formulas against this backend's
    /// own W3C formulas — two implementations of the same spec agreeing to a float rounding step, which
    /// says nothing about whether Apple's non-separable blends agree with the spec. That comparison has
    /// never been run. Hand-rolling `hue`/`saturation`/`color`/`luminosity` here is the conservative
    /// choice: it is independently cross-checked (against the GPU shader and against hand-computed
    /// values from a Python transcription of the W3C formulas), where Apple's versions are unmeasured.
    /// Measuring them against `CGBlendMode` directly is a real future experiment, not a foregone
    /// conclusion — if they agree, these four could take the same faster path `exclusion` already does.
    var coreGraphicsBlendMode: CGBlendMode? {
        switch self {
        // `clipToBelow` is source-over plus a mask, and the tree has already turned it into exactly
        // that (`compositedMode`) — so it cannot arrive here. Named rather than left to a `default`
        // so that a genuinely new mode still fails to compile until someone decides what it draws.
        case .normal, .clipToBelow: return .normal
        case .multiply:    return .multiply
        case .screen:      return .screen
        case .overlay:     return .overlay
        case .darken:      return .darken
        case .lighten:     return .lighten
        case .hardLight:   return .hardLight
        case .difference:  return .difference
        case .exclusion:   return .exclusion
        // "CoreGraphics disagrees about these," not "CoreGraphics lacks these" — measured 141/249/16
        // against the spec; see `handRolledChannel` and the measured table in
        // `CompositorParityLogicTests`.
        case .colorDodge, .colorBurn, .softLight: return nil
        // Absent, not awkward: `CGBlendMode` has no case for any of these seven.
        case .add, .subtract, .linearLight: return nil
        case .vividLight, .pinLight, .linearBurn, .divide, .lighterColor, .darkerColor: return nil
        // CoreGraphics *does* have cases for these four — hand-rolled by choice, not by measured
        // disagreement. Apple's non-separable implementations have never been measured against the
        // spec; see `handRolledTriple`'s doc comment for what the sweep below actually compared.
        case .hue, .saturation, .color, .luminosity: return nil
        }
    }

    /// Whether this mode needs the whole RGB triple rather than one channel at a time — §7 Tier 2's
    /// trap. `CoreGraphicsCompositor.drawHandRolled` reads this to decide which of `handRolledChannel`
    /// (called three times, once per channel) or `handRolledTriple` (called once, given all three) is
    /// the right shape of call for a hand-rolled mode. `Composite.metal` needs no such branch — its
    /// `blendChannels` already takes and returns a `float3`, so a non-separable formula fits the exact
    /// same call site a separable one does and the split is CPU-only.
    fileprivate var isNonSeparable: Bool {
        switch self {
        case .hue, .saturation, .color, .luminosity, .lighterColor, .darkerColor: return true
        default: return false
        }
    }

    /// The per-channel blend for every *separable* hand-rolled mode, unpremultiplied on both sides.
    /// Must agree with the matching case of `blendChannels` in `Composite.metal`, and is the only
    /// place in this backend where separable blend arithmetic is written out.
    ///
    /// **Two different reasons a mode lands here, and the second one is a finding.**
    ///
    /// `add`, `subtract`, `linearLight`, and Tier 2's `vividLight`, `pinLight`, `linearBurn` and
    /// `divide` are here because `CGBlendMode` has no case for them.
    ///
    /// `colorDodge`, `colorBurn` and `softLight` are here because Apple's cases *exist and disagree*.
    /// Sweeping all fourteen Tier 1 modes over 4096 (colour, alpha) pairs put every other mode within
    /// one step of the shader and these three at **141, 249 and 16**. That is not a rounding regime;
    /// it is two different formulas. CoreGraphics implements the PDF 1.4 originals, where the
    /// divisions have no zero-backdrop case — so `colorDodge` lifts a black backdrop to white at
    /// `cs == 1` where the modern rule keeps it black, `colorBurn` does the mirror of that at
    /// `cs == 0`, and `softLight` uses a different `D(cb)` curve altogether. W3C Compositing Level 1
    /// (equivalently PDF 2.0) added the guards, and it is what Photoshop and CSP do, which settles
    /// which of the two an artist reaching for Color Dodge means.
    ///
    /// So the shader is the correct one and this backend follows it, rather than the reference being
    /// "whatever Apple ships". Worth stating plainly because §5.1 calls the CoreGraphics path the
    /// byte-for-byte definition of correct: that holds for the *walk* — the order, the buffers, the
    /// alpha — and not for the blend functions themselves, where the spec is the authority and both
    /// backends are implementations of it.
    ///
    /// `vividLight` and `pinLight` route through `colorDodgeChannel`/`colorBurnChannel` and
    /// `min`/`max` rather than restating dodge-and-burn or darken-and-lighten, for the same reason
    /// `Composite.metal`'s versions call `blendColorDodge`/`blendColorBurn`: one definition of each,
    /// so a future fix to Color Dodge cannot fix it in three places and miss a fourth.
    fileprivate func handRolledChannel(backdrop cb: Float, source cs: Float) -> Float {
        switch self {
        case .add:         return min(1, cb + cs)
        case .subtract:    return max(0, cb - cs)
        case .linearLight: return min(1, max(0, cb + 2 * cs - 1))
        case .colorDodge:  return colorDodgeChannel(backdrop: cb, source: cs)
        case .colorBurn:   return colorBurnChannel(backdrop: cb, source: cs)
        case .softLight:   return softLightChannel(backdrop: cb, source: cs)
        // Vivid Light: Color Burn below mid-grey, Color Dodge above it, each fed the doubled,
        // re-centred source — the same split Hard Light makes between Multiply and Screen.
        case .vividLight:
            return cs <= 0.5 ? colorBurnChannel(backdrop: cb, source: 2 * cs)
                              : colorDodgeChannel(backdrop: cb, source: 2 * cs - 1)
        // Pin Light: Darken below mid-grey, Lighten above it, same doubled-source split as above —
        // the "which of two ordinary modes" family Vivid Light belongs to as well.
        case .pinLight:
            return cs <= 0.5 ? min(cb, 2 * cs) : max(cb, 2 * cs - 1)
        // Linear Burn is Linear Dodge's mirror: `cb + cs - 1` where Add is `cb + cs`, clamped the
        // same way at the end the arithmetic can leave the [0, 1] range rather than the start.
        case .linearBurn:  return max(0, cb + cs - 1)
        // Divide mirrors Color Dodge's guard order exactly, with the pole moved from `1 - cs` to
        // `cs` itself: a black backdrop stays black regardless of the source (checked first, so it
        // wins over the next guard even at `cs == 0`), and a near-zero source saturates to white
        // rather than dividing by it.
        case .divide:
            if cb <= 0 { return 0 }
            if cs <= 0 { return 1 }
            return min(1, cb / cs)
        case .exclusion:   return cb + cs - 2 * cb * cs
        default:           return cs
        }
    }

    /// The RGB-triple blend for the non-separable modes (`isNonSeparable`), unpremultiplied on both
    /// sides. Must agree with the matching case of `blendChannels` in `Composite.metal` — which needs
    /// no separate function for these the way this backend does, since a Metal `float3` already
    /// carries all three channels through the one call site both shapes of formula share.
    ///
    /// **All six cases here are live in this backend today.** `lighterColor` and `darkerColor` have no
    /// `CGBlendMode` case, so `draw` always reaches them through this function — the same
    /// "absent, not awkward" reason `add` is hand-rolled. `hue`, `saturation`, `color` and `luminosity`
    /// *do* have `CGBlendMode` cases, but `coreGraphicsBlendMode` returns `nil` for all four regardless
    /// — so `draw` reaches these four cases every time too, not as insurance against a future
    /// regression but as the ordinary production path.
    ///
    /// That is a choice, not a measured disagreement: Apple's non-separable implementations have never
    /// been checked against the W3C spec. The nearest measurement,
    /// `CompositorParityLogicTests.testEveryBlendModeAgreesBetweenTheBackends`, compares the GPU shader
    /// against this CPU backend — and since this backend already hand-rolls these four, that sweep
    /// compares the app's own two implementations of the spec against each other, not against
    /// CoreGraphics. Its reported deltas for them (hue 1, saturation 0, color 1, luminosity 1) are float
    /// rounding between our own two paths and say nothing about Apple's versions (contrast `exclusion`,
    /// which *does* cross `CGBlendMode` and whose delta of 0 is a real CoreGraphics-versus-spec
    /// measurement — see `coreGraphicsBlendMode`'s doc comment). Whether Apple's cases agree with the
    /// spec is a genuine open question and a future experiment, not yet run either direction.
    ///
    /// W3C Compositing and Blending Level 1's non-separable formulas, restated here rather than
    /// summarised: `Lum`/`Sat` read a colour's luminosity and saturation, `ClipColor` pulls an
    /// out-of-gamut colour back into `[0, 1]` along the axis that keeps its `Lum`, `SetLum`/`SetSat`
    /// transplant one colour's luminosity or saturation onto another's channels. Hue keeps the
    /// source's hue and saturation but the backdrop's luminosity; Saturation keeps the backdrop's hue
    /// and luminosity but the source's saturation; Color keeps the source's hue and saturation *and*
    /// the backdrop's luminosity in one step; Luminosity is Color with the two swapped.
    ///
    /// `setSat`'s spec pseudocode sorts the channels into min/mid/max and rewrites each in place; the
    /// version below is the same function stated as one affine remap of the whole triple —
    /// `(c - cMin) * s / (cMax - cMin)` sends `cMin` to 0, `cMax` to `s`, and everything between to the
    /// spec's `Cmid` formula, by construction — which needs no sort and no per-channel branch, on
    /// either backend.
    fileprivate func handRolledTriple(backdrop cb: Triple, source cs: Triple) -> Triple {
        switch self {
        case .hue:          return setLum(setSat(cs, sat(cb)), lum(cb))
        case .saturation:   return setLum(setSat(cb, sat(cs)), lum(cb))
        case .color:        return setLum(cs, lum(cb))
        case .luminosity:   return setLum(cb, lum(cs))
        // Whole-triple luminosity picks whole-triple winner — not a per-channel max/min, which is
        // what `lighten`/`darken` already are and would not need a new case to express.
        case .lighterColor: return lum(cs) >= lum(cb) ? cs : cb
        case .darkerColor:  return lum(cs) <= lum(cb) ? cs : cb
        default:            return cs
        }
    }
}

/// `(r, g, b)`, unpremultiplied and in `[0, 1]` on the way in — the shape `handRolledTriple` and its
/// W3C helpers pass around. A named tuple rather than `SIMD3<Float>`: nothing here is dispatched to
/// the GPU, and elementwise arithmetic written out per component is what the rest of this file
/// already does in `drawHandRolled`'s loop.
private typealias Triple = (r: Float, g: Float, b: Float)

/// Shared by `handRolledChannel`'s `colorDodge` case and its `vividLight` case, so Color Dodge has one
/// definition instead of two that could drift apart. Body unchanged from phase 5a.
private func colorDodgeChannel(backdrop cb: Float, source cs: Float) -> Float {
    if cb <= 0 { return 0 }
    if cs >= 1 { return 1 }
    return min(1, cb / (1 - cs))
}

/// Shared by `handRolledChannel`'s `colorBurn` case and its `vividLight` case. Body unchanged from
/// phase 5a.
private func colorBurnChannel(backdrop cb: Float, source cs: Float) -> Float {
    if cb >= 1 { return 1 }
    if cs <= 0 { return 0 }
    return 1 - min(1, (1 - cb) / cs)
}

/// Body unchanged from phase 5a; factored out alongside the other two so all three hand-rolled Tier 1
/// formulas live at the same scope as the Tier 2 callers that might one day want them.
private func softLightChannel(backdrop cb: Float, source cs: Float) -> Float {
    if cs <= 0.5 { return cb - (1 - 2 * cs) * cb * (1 - cb) }
    // The cubic below a quarter keeps the curve's slope finite at zero, where `sqrt` is vertical and
    // would band on dark backdrops.
    let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : sqrt(cb)
    return cb + (2 * cs - 1) * (d - cb)
}

// MARK: - W3C's non-separable helpers (§7 Tier 2)
//
// `Lum`, `Sat`, `ClipColor`, `SetLum`, `SetSat` — free functions rather than `Triple` methods because
// nothing else in this file hangs functions off a tuple type, and because it keeps them visually
// grouped with the spec section they come from rather than scattered through `BlendMode`'s extension.

/// The perceptual weighting every one of Tier 2's non-separable formulas keys off — Hue, Saturation,
/// Color and Luminosity all call it, and so do `lighterColor`/`darkerColor`, so "how bright is this
/// colour" has exactly one definition in this file. Must agree with `lum` in `Composite.metal`.
private func lum(_ c: Triple) -> Float { 0.3 * c.r + 0.59 * c.g + 0.11 * c.b }

private func sat(_ c: Triple) -> Float { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }

/// Pulls an out-of-gamut colour back into `[0, 1]` along the line through it and its own `Lum` —
/// `SetLum` is the only caller, and always on a colour it just shifted uniformly, which is what can
/// push a channel negative or past 1 in the first place.
///
/// The two `max(_, 1e-6)` guards exist only for the case both branches meet: a colour whose `Lum`
/// equals its `min`/`max` is one whose three channels are already equal, and there `c - l` is exactly
/// zero for every channel — so the guard changes a `0 / 0` into a `0 / epsilon`, not the result.
private func clipColor(_ c: Triple) -> Triple {
    let l = lum(c)
    let n = min(c.r, c.g, c.b), x = max(c.r, c.g, c.b)
    var result = c
    if n < 0 {
        let scale = l / max(l - n, 1e-6)
        result = (l + (result.r - l) * scale, l + (result.g - l) * scale, l + (result.b - l) * scale)
    }
    if x > 1 {
        let scale = (1 - l) / max(x - l, 1e-6)
        result = (l + (result.r - l) * scale, l + (result.g - l) * scale, l + (result.b - l) * scale)
    }
    return result
}

private func setLum(_ c: Triple, _ l: Float) -> Triple {
    let d = l - lum(c)
    return clipColor((c.r + d, c.g + d, c.b + d))
}

/// See `handRolledTriple`'s doc comment for why this is one affine remap rather than the spec's
/// sort-and-rewrite — the two are the same function.
private func setSat(_ c: Triple, _ s: Float) -> Triple {
    let cMax = max(c.r, c.g, c.b), cMin = min(c.r, c.g, c.b)
    guard cMax > cMin else { return (0, 0, 0) }
    let scale = s / (cMax - cMin)
    return ((c.r - cMin) * scale, (c.g - cMin) * scale, (c.b - cMin) * scale)
}

// MARK: - The Core Graphics reference

enum CoreGraphicsCompositor {

    static func composite(_ request: RenderRequest) -> CGImage? {
        let size = request.canvasSize
        guard size.width > 0, size.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: size)

        let image = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
            .image { context in
                // **Skipped for a chunk continuation, and `background` is still the paper**
                // (RENDER.md §3.4). The accumulator leaf this walk is about to draw already holds
                // the paper; filling it again would lay a translucent one down twice. Everything
                // downstream still reads `request.background` — `paperInBackdrop` below, and
                // `gradedInkOverPaper`, which is the whole reason the field is not simply nil here.
                // `UIGraphicsImageRenderer` starts transparent, so skipping the fill is all it takes.
                if request.continuation == nil { fillBackground(request.background) }
                // **`paperInBackdrop` is `request.background != nil`, and it is the only reason an
                // `.ink` effect has anything to do** — EFFECT_BACKDROP.md §3 option A. It says "the
                // accumulator this walk is about to build starts with the canvas paper in it", which
                // is what makes alpha stop meaning coverage. Every buffered scope below passes
                // false, and that is exact: such a scope's accumulator *is* its own assembled
                // composite, which has never held the paper, so re-walking for an effect inside one
                // would be work with no difference to show for it.
                //
                // **A root walk with no background passes false too, and there the claim is weaker
                // than it reads.** The sandwich's `above` half is exactly that — `makeSandwichRecipe`
                // builds it with `background: nil` on purpose — so an `.ink` effect in it grades the
                // accumulator as it stands, which holds only what is *above* the active layer rather
                // than everything below the effect node. A truncated ink, not the ink. That is an
                // approximation, it is mid-stroke only, it predates the paper landing in the
                // composite, and it snaps to the exact picture on lift when `full` is what the canvas
                // shows — the same trade `SandwichLogicTests` already measures for a faded group.
                // Named here rather than fixed: fixing it means a second cut of the tree per stroke
                // frame, which is a cost this branch did not measure.
                draw(request.tree, of: request, in: bounds, context: context,
                     paperInBackdrop: request.background != nil)
            }
        return image.cgImage
    }

    /// **The canvas paper, into whatever context the caller has made current** — nothing at all when
    /// the request has none.
    ///
    /// `background.rect`, not the buffer's bounds: the paper is the artwork rect and the padding
    /// margin is not paper — see `RenderBackground.rect` for why that is the decision and not an
    /// oversight. Identical to filling the whole buffer on every document with no padding, which is
    /// the default and every fixture in the suite. The rect is already whole pixels and symmetric on
    /// all four sides, so this agrees with the Metal fill without either side rounding or flipping
    /// anything.
    ///
    /// **One function because it has two callers** — the top of the walk, and `gradedInkOverPaper`,
    /// which rebuilds the same paper underneath a graded ink. Two spellings of a fill whose only
    /// subtlety is *which rectangle* is exactly the pair that drifts apart.
    private static func fillBackground(_ background: RenderBackground?) {
        guard let background else { return }
        background.color.setFill()
        UIRectFill(background.rect)
    }

    /// Draws one bottom-to-top stack into the context the caller has already made current.
    ///
    /// **Groups do not get their own buffer while they are still transparent parentheses, and that is
    /// what makes phase 2's gate reachable.** Source-over is associative, so compositing a group's
    /// children into a scratch buffer and then that buffer over the backdrop is the same *arithmetic*
    /// as drawing the children straight onto the backdrop — but it is not the same *bytes*: the
    /// intermediate rounds to 8-bit premultiplied once more than the direct path, and a group nested
    /// three deep rounds three more times. Against a gate that says "byte-identical", a scratch buffer
    /// per folder would fail on documents whose only sin is having folders in them.
    ///
    /// So a group allocates only when it actually changes the result, and `RenderNode.needsOwnBuffer`
    /// is that decision — stated once, for this backend and Metal's both. All three of its clauses
    /// are reachable as of phase 5; a folder nobody has touched is still opacity 1, normal and
    /// isolated over nothing that blends, so it takes the direct path and the derived tree still
    /// provably composites to what the deleted flat walk composited. §5.3's "never allocate one per
    /// layer" wants exactly this, and `PerfBaselineTests` measures it.
    private static func draw(_ nodes: [RenderNode], of request: RenderRequest, in bounds: CGRect,
                             context: UIGraphicsImageRendererContext, paperInBackdrop: Bool) {
        for node in nodes {
            switch node.content {
            case .leaf(let layerIndex):
                // A leaf's flag gates the leaf; a group's gates its whole subtree (see the `.node`
                // case). The deleted flat walk's `where layer.isVisible` is exactly this test, and
                // `CompositorParityLogicTests.flatWalkComposite` still holds it to that.
                guard node.isVisible else { continue }
                // **§4.4's stack layer, and it is reached before `sources` rather than after.** An
                // effect layer holds no pixels — the snapshot elides it — so it has no source to
                // find, and the guard below would drop it as an empty leaf. What it has is a grade
                // over the backdrop this walk has accumulated so far, which is the input-resolution
                // rule the whole wrapper consists of.
                if let effect = node.effect {
                    // **§3 option A's re-walk, and the whole of it is choosing an input.** An `.ink`
                    // effect wants everything below this node *without* the paper, which is exactly
                    // the tree `split(atLeaf:)` already produces for the sandwich's lower half — the
                    // same cut, composited onto transparency instead of onto the canvas. Nil
                    // whenever the accumulator is already paper-free, which is every buffered scope,
                    // and nil for a `.backdrop` effect, which is ten of the thirteen.
                    //
                    // Switched exhaustively rather than tested against `.ink`: a third `Input` case
                    // would compile clean against `== .ink` and be routed silently as `.backdrop`
                    // here, in `MetalCompositor.encode` and in `peakCompositeTextures` alike — three
                    // places that each decide something different and each need their own answer.
                    // That is the hand-maintained-list rot CLAUDE.md records from `CanvasManager`.
                    let inkBelow: [RenderNode]?
                    switch effect.input {
                    case .ink:
                        inkBelow = paperInBackdrop
                            ? request.tree.split(atLeaf: layerIndex)?.below.substitutingChunkAccumulator(of: request)
                            : nil
                    case .backdrop:
                        inkBelow = nil
                    }
                    grade(effect, by: node, of: request, in: bounds, context: context, inkBelow: inkBelow)
                    continue
                }
                guard request.sources.indices.contains(layerIndex),
                      let source = request.sources[layerIndex] else { continue }
                // **A leaf blends as it is drawn** (`RenderNode.blendMode`): its mode is an argument
                // to this one draw, against whatever the walk has accumulated underneath. That is
                // the whole difference from the `.node` case below, which blends once against the
                // backdrop after assembling.
                //
                // A masked leaf needs no buffer of its own: the mask multiplies the one image it is
                // about to draw (§6.1 — at render time, never into the layer's own pixels).
                let pixels = masked(source.image, by: node, of: request)
                draw(UIImage(cgImage: pixels, scale: 1, orientation: .up),
                     mode: node.blendMode, opacity: node.opacity, in: bounds, context: context)

            case .node(let op, let inputs):
                // **A group's own `isVisible` gates its subtree** (§4.1) — a hidden group is a
                // subtree that is not walked, not a set of children that were each written hidden.
                // `toggleFolderVisibility` used to write through to every descendant, which made the
                // folder's flag a duplicate of its children's and made hide-then-show destroy the
                // per-layer visibility the artist had set by hand; phase 4a stopped that, and this is
                // the compositor's half of the same change. A child re-shown inside a hidden group
                // therefore does not draw, which is a deliberate change to shipped behaviour and is
                // pinned by `testAChildReShownInsideAHiddenFolderIsGatedByTheGroup`.
                //
                // Costs nothing to skip: the whole subtree is dropped before any buffer is
                // considered, so hiding a group is the cheapest thing in this walk rather than a
                // buffer full of nothing.
                guard node.isVisible else { continue }
                if !node.needsOwnBuffer {
                    // The direct path is also the pass-through path: children drawn straight onto
                    // the backdrop blend against it, which is what "pass-through" means.
                    // `needsOwnBuffer` guarantees `node.blendMode == .normal` here, so there is no
                    // group mode being silently dropped — a group that blends always buffers — and
                    // it guarantees `op == .stack`, so no fold is being dropped either.
                    for input in inputs {
                        // Straight onto the caller's accumulator, so the paper is still in it.
                        draw(input, of: request, in: bounds, context: context,
                             paperInBackdrop: paperInBackdrop)
                    }
                    continue
                }
                // Render the node's own composite, then apply its opacity and its mode once to the
                // finished thing — the alternative, applying either per child, is a different and
                // wrong picture wherever children overlap.
                //
                // **The scratch buffer starts transparent whatever `isIsolated` says, and that
                // is a decision rather than an omission.** A pass-through group that also
                // buffers — because it is faded, or because it has a mode of its own — cannot
                // have both: compositing children against the backdrop *and then* compositing
                // the result over that same backdrop counts it twice. Photoshop resolves the
                // same conflict the same way (choosing any mode other than Pass Through is what
                // makes a group isolated there), so a buffered group is an isolated group here,
                // and `isIsolated` is what decides the case that is still free to differ:
                // opacity 1, mode normal, something inside that blends.
                // §4.4's second wrapper (phase 9b): if this node carries a grade, it runs inside the
                // same renderer, immediately after the fold assembles the node's own composite —
                // `grade` reads `inner.currentImage` (that composite) as its backdrop and `.copy`s
                // the graded result back into `inner`, exactly mirroring how the leaf case above
                // grades `context.currentImage` in place. That makes `assembled` the *graded*
                // composite by the time this closure returns.
                let assembled = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
                    .image { inner in
                        fold(op, inputs, of: request, in: bounds, context: inner)
                        if let effect = node.effect {
                            // No `inkBelow`: a node with a grade always buffers
                            // (`needsOwnBuffer`), so `inner` is its own assembled composite and has
                            // never had the paper in it. The ink and the backdrop are the same
                            // image here, which is why §4's table never has to ask about a node.
                            grade(effect, by: node, of: request, in: bounds, context: inner, inkBelow: nil)
                        }
                    }
                // The node's mask clips the node, so it lands on the assembled composite — which is
                // the same rule its opacity and its blend mode follow, and the reason
                // `needsOwnBuffer` counts a mask as a reason to allocate. It clips the *result* of
                // a fold, never the slots that went into it, for exactly the reason it clips a
                // group rather than its children.
                //
                // **Skipped when this node has an effect.** `grade` already consumed `node.masks` and
                // `node.opacity` internally to crossfade the graded pixels back toward the ungraded
                // fold result (`compositeEffectMix`'s mix-not-source-over math) — reapplying the mask
                // here and `node.opacity` below would be the same double-application the 9a leaf case
                // avoids by `continue`-ing straight past its own mask/opacity draw once it grades.
                let clipped: UIImage
                if node.effect != nil {
                    clipped = assembled
                } else {
                    clipped = assembled.cgImage.map { masked($0, by: node, of: request) }
                        .map { UIImage(cgImage: $0, scale: 1, orientation: .up) } ?? assembled
                }
                draw(clipped, mode: node.blendMode, opacity: node.effect != nil ? 1 : node.opacity,
                     in: bounds, context: context)
            }
        }
    }

    /// **One node's input slots, combined by its op, into the buffer the caller has made current.**
    ///
    /// This is the whole of phase 8's change to this backend, and it is a change to the *walk* rather
    /// than to any arithmetic: §4.3's `Mix(A, B, .multiply)` is deliberately the same math as stacking
    /// B over A with multiply, so the fold reuses `draw(_:mode:opacity:in:context:)` — the same call a
    /// blending leaf and a blending group already go through — and no new primitive exists on either
    /// backend.
    ///
    /// **Slot 0 is drawn straight into the accumulator and every later slot gets a buffer of its own.**
    /// §4.3 says an input slot is always isolated, and slot 0 already is: the accumulator was made
    /// transparent one line above and nothing has touched it, so a separate buffer for it would buy
    /// nothing but one more 8-bit requantization. The later slots genuinely need one — the fold is
    /// between two *finished* composites, and drawing slot 1's contents one at a time onto slot 0
    /// would blend each of them against slot 0 in turn, which is `.stack` wearing a mode.
    ///
    /// `.stack` never takes the isolating branch, so it still runs the single-shared-accumulator loop
    /// it always did, byte for byte — the common case does not start paying a buffer per child.
    private static func fold(_ op: CompositorOp, _ inputs: [[RenderNode]], of request: RenderRequest,
                             in bounds: CGRect, context: UIGraphicsImageRendererContext) {
        for (slot, input) in inputs.enumerated() {
            guard case .mix(let mode) = op, slot > 0 else {
                // `paperInBackdrop: false` throughout `fold`, and it is not a choice: `fold` is
                // reached only from the buffered branch, whose scratch buffer starts transparent
                // whatever `isIsolated` says. There is no paper in here to take out again.
                draw(input, of: request, in: bounds, context: context, paperInBackdrop: false)
                continue
            }
            let isolated = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
                .image { inner in draw(input, of: request, in: bounds, context: inner, paperInBackdrop: false) }
            // Opacity 1: the node's own fade applies once to the finished fold, up in `draw`. Fading
            // a slot on its way into the fold would be the per-child mistake group opacity already
            // refuses to make.
            draw(isolated, mode: mode, opacity: 1, in: bounds, context: context)
        }
    }

    /// **§4.4's stack layer: one effect over the backdrop accumulated so far in this container.**
    ///
    /// *This container* is not a rule stated here — it is `context`. A buffered group runs this walk
    /// inside its own `UIGraphicsImageRenderer`, so `currentImage` is the group's own accumulator and
    /// the grade cannot see past it; at the root it is the canvas, background included, which is what
    /// an adjustment layer at the top of a stack grades in Photoshop. `RenderNode.enclosesABlend` is
    /// what guarantees an isolated group has that buffer, and carries the argument.
    ///
    /// The graded pixels **replace** the backdrop rather than compositing over it, mixed back by
    /// opacity and coverage — see `compositeEffectMix` in `Composite.metal`, which is the same three
    /// lines and carries the reasoning for why source-over would be wrong here.
    ///
    /// Slow, and for `drawHandRolled`'s reason rather than by oversight: it snapshots the canvas,
    /// reads it back, grades every pixel in Swift and writes a third buffer. This backend is the
    /// oracle the shader is measured against and the fallback on a device with no Metal, so it may be
    /// slow and may not be approximate. §5.1 is the argument for where this runs at interactive rates.
    private static func grade(_ effect: Effect, by node: RenderNode, of request: RenderRequest,
                              in bounds: CGRect, context: UIGraphicsImageRendererContext,
                              inkBelow: [RenderNode]?) {
        let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
        guard width > 0, height > 0 else { return }
        // Read before either arm writes anything: both crossfade their result back over this exact
        // image, and the ink arm runs a whole sub-composite of its own before it needs it.
        guard let backdropImage = context.currentImage.cgImage,
              let backdrop = premultipliedBytes(backdropImage, width: width, height: height)
        else { return }

        // **The two input-resolution rules meet here and nowhere else.** One produces the graded
        // *backdrop*, the other the paper with the graded ink laid on it — and from `mixBack`'s point
        // of view they are the same thing: the picture this container would show if everything the
        // adjustment layer covers had been replaced by the grade.
        let graded: [UInt8]
        if let inkBelow {
            guard let replaced = gradedInkOverPaper(effect, below: inkBelow, of: request,
                                                    in: bounds, width: width, height: height)
            else { return }
            graded = replaced
        } else {
            // The one call both §4.4 wrappers make, given the one texture their input-resolution
            // rules differ about. Nothing here looks inside the `Effect`; `Effect.swift` resolved it
            // once.
            graded = EffectReference.apply(effect, to: backdrop, width: width, height: height)
        }
        mixBack(graded, over: backdrop, by: node, of: request, in: bounds,
                context: context, width: width, height: height)
    }

    /// **The graded picture crossfaded back over the ungraded one by `node.opacity × mask`** — the
    /// mix `compositeEffectMix` is the shader twin of, and the single place either input path ends.
    ///
    /// Opacity and coverage read as an **amount**, never as coverage: at 0 this is the backdrop
    /// exactly, at 1 the grade exactly, whatever the graded pixel's own alpha happens to be.
    /// Source-over is a different function wherever the grade is not opaque — a half-covered Sobel
    /// that emits transparency reads as the untouched backdrop under `over` and as half way to the
    /// paper under this — which is why the ink path shares this rather than compositing its own
    /// result over the accumulator, and why it needs no clipped copy of the graded image.
    private static func mixBack(_ graded: [UInt8], over backdrop: [UInt8], by node: RenderNode,
                                of request: RenderRequest, in bounds: CGRect,
                                context: UIGraphicsImageRendererContext, width: Int, height: Int) {
        // Same resolution the GPU path uploads, for `MaskResolver`'s reason — the threshold is a step
        // function and the two backends cannot be allowed to land on opposite sides of it.
        let coverage = node.masks.isEmpty ? nil : MaskResolver.coverage(for: node.masks, of: request)
        let opacity = Float(node.opacity)

        var result = backdrop
        for pixel in 0..<(width * height) {
            let amount = opacity * (coverage.map { Float($0.coverage[pixel]) / 255 } ?? 1)
            // No amount is the backdrop, exactly — worth the branch rather than four multiplies by
            // zero, since outside the mask is most of the canvas in most documents.
            guard amount > 0 else { continue }
            for channel in 0..<4 {
                let offset = pixel * 4 + channel
                let base = Float(backdrop[offset]) / 255
                let value = base + (Float(graded[offset]) / 255 - base) * amount
                result[offset] = UInt8((min(max(value, 0), 1) * 255).rounded(.toNearestOrEven))
            }
        }

        guard let image = makeImage(fromPremultiplied: result, width: width, height: height) else { return }
        // `.copy`, as `drawHandRolled` ends: this image *is* the accumulated backdrop, regraded, so it
        // replaces the context rather than being composited onto what it was computed from.
        UIImage(cgImage: image, scale: 1, orientation: .up).draw(in: bounds, blendMode: .copy, alpha: 1)
    }

    /// **EFFECT_BACKDROP.md §3 option A: the re-walk.** Outline, Bloom and Sobel do not read colour,
    /// they read *shape* — `src.a > threshold`, a luminance threshold, a gradient magnitude — and the
    /// accumulator's alpha stopped being the ink's coverage the moment the paper was filled into it.
    /// Over an opaque backdrop Outline is a complete no-op and Bloom makes the whole canvas a source.
    ///
    /// So this composites the same cut of the tree the sandwich's lower half already uses, onto
    /// transparency, and hands *that* to the kernel. **The three shaders need no change** — what
    /// changes is which image they are given, which is the entire point of the option that was
    /// chosen: A adds no state to either backend, and B (a coverage texture) and C (two accumulators)
    /// add state both would have to maintain identically against a byte-for-byte gate.
    ///
    /// **The graded ink *replaces* what is below it, on the same paper the walk started from** —
    /// which is what an adjustment layer means, and it is `mixBack` that lays the result down.
    ///
    /// The equality this rests on is not `accumulator == paper ⊕ ink`; it is the weaker and provable
    /// `accumulator == paper ⊕ split(atLeaf:).below`. The walk is a strict bottom-to-top loop over
    /// the siblings and the accumulator is written by nothing but the background fill and that loop,
    /// so at this node the accumulator holds the paper plus precisely the nodes `below` names. Laying
    /// the paper back down and drawing the grade on it therefore discards exactly the sub-tree the
    /// adjustment layer is replacing, and nothing else. The enclosing-folder case is safe for a
    /// reason stated elsewhere and worth naming: `enclosesABlend` answers true on `$0.effect != nil`,
    /// so an *isolated* folder holding an effect leaf always buffers and never reaches this path —
    /// only a pass-through folder does, and `split(atLeaf:)`'s half of one is an identity wrapper.
    /// `testAFadedPassThroughFolderDoesNotFadeTwiceUnderAnInkEffect` is what notices if that changes.
    ///
    /// **This composited the graded ink *over* the accumulator until 2026-08-27, and that was the
    /// defect.** The ink was drawn a second time, so a 60%-alpha black square over white paper read
    /// 102 beside an Outline layer and 41 under one — the coverage going 0.6 → 1−0.4² = 0.84. Bloom
    /// defaults to `.ink`, so that darkening was shipped behaviour for every bloom document, and it
    /// was not confined to non-opaque ink: an `.ink` effect that *replaces* its input rather than
    /// adding to it could not replace anything either, and the artwork stayed visible beneath the
    /// result. The case that showed it was a Sobel set to `.ink` — **a setting that existed for a few
    /// hours on 2026-08-27 and that the owner then deleted** (EFFECT_BACKDROP.md §5.2), so Sobel is
    /// fixed `.backdrop` now and never reaches this path at all. Outline is the `.ink` effect that
    /// still does, and `testAFadedPassThroughFolderDoesNotFadeTwiceUnderAnInkEffect` names it.
    ///
    /// One consequence is inherent to §3's option A rather than to this correction, and is pinned by
    /// `testABlendModeBelowAnInkEffectIsReplacedNotPreserved`: a non-normal blend mode below an ink
    /// effect blends against transparency in the sub-walk instead of against the paper, so a
    /// `difference` layer that reads cyan on its own reads red under an Outline layer. Option C (two
    /// accumulators) is the only shape that preserves it, and §3 priced and rejected it.
    ///
    /// `node.blendMode` is deliberately not consulted, exactly as the backdrop path does not: an
    /// effect layer's mode has never meant anything, and giving it one here would make it mean
    /// something for three of the thirteen effects only.
    private static func gradedInkOverPaper(_ effect: Effect, below: [RenderNode],
                                           of request: RenderRequest, in bounds: CGRect,
                                           width: Int, height: Int) -> [UInt8]? {
        // The same sources, the same masks, the same frame — only the tree is cut and the background
        // is dropped. `composite` re-enters this file's own walk, so the sub-walk is the walk: there
        // is no second implementation of grouping, blending or masking to keep in step.
        let inkRequest = RenderRequest(tree: below, sources: request.sources,
                                       contentVersions: request.contentVersions,
                                       maskStacks: request.maskStacks, frame: request.frame,
                                       canvasSize: request.canvasSize, background: nil,
                                       quality: request.quality)
        guard let inkImage = composite(inkRequest),
              let ink = premultipliedBytes(inkImage, width: width, height: height) else { return nil }

        let gradedInk = EffectReference.apply(effect, to: ink, width: width, height: height)
        guard let gradedInkImage = makeImage(fromPremultiplied: gradedInk, width: width, height: height)
        else { return nil }
        // `fillBackground` rather than a second spelling of the fill, and the renderer starts
        // transparent, so a padded canvas's margin is left transparent here exactly as it is at the
        // top of the walk — which is what keeps the margin out of the crossfade.
        let replaced = UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat())
            .image { _ in
                fillBackground(request.background)
                UIImage(cgImage: gradedInkImage, scale: 1, orientation: .up)
                    .draw(in: bounds, blendMode: .normal, alpha: 1)
            }
        guard let replacedImage = replaced.cgImage else { return nil }
        return premultipliedBytes(replacedImage, width: width, height: height)
    }

    /// `image` with this node's masks applied, or `image` unchanged when it has none.
    ///
    /// Falls back to the unmasked pixels if a resolution fails, which is the same direction every
    /// other degenerate case in this file takes: show the artwork, not a hole. A mask that cannot
    /// resolve is one whose sources have gone (§6.6), and an unmasked layer is what that is defined
    /// to produce.
    private static func masked(_ image: CGImage, by node: RenderNode, of request: RenderRequest) -> CGImage {
        guard !node.masks.isEmpty,
              let mask = MaskResolver.coverage(for: node.masks, of: request),
              let clipped = MaskResolver.apply(mask, to: image) else { return image }
        return clipped
    }

    /// One image onto the current context, at `opacity`, in `mode` — the single place this backend
    /// applies a blend, for leaves and for assembled groups alike.
    private static func draw(_ image: UIImage, mode: BlendMode, opacity: Double,
                             in bounds: CGRect, context: UIGraphicsImageRendererContext) {
        if let cgMode = mode.coreGraphicsBlendMode {
            // Via `UIImage` rather than `CGContext.draw` so the top-left origin and the alpha
            // application are literally the same call the deleted flat walk made. A byte-identical
            // gate is not the place to hand-roll a coordinate flip.
            image.draw(in: bounds, blendMode: cgMode, alpha: CGFloat(opacity))
        } else {
            drawHandRolled(image, mode: mode, opacity: opacity, in: bounds, context: context)
        }
    }

    /// `add`, `subtract`, `linearLight` and Tier 2's hand-rolled modes, which CoreGraphics cannot
    /// express (see `BlendMode.coreGraphicsBlendMode`), computed a pixel at a time and stamped over
    /// the context.
    ///
    /// **This is slow on purpose, and the alternative was worse.** It snapshots the whole canvas,
    /// reads two buffers back, and writes a third — three canvas-sized allocations for one draw,
    /// where a CG primitive is one blit. The GPU is the answer for these modes at interactive rates
    /// (§5.1 is entirely this argument) and this backend's job is to be *right*: it is the oracle the
    /// shader is measured against and the fallback on a device with no Metal, so a fast approximation
    /// here would corrupt the measurement it exists to provide.
    ///
    /// The arithmetic is `blendOver`'s from `Composite.metal`, term for term, including the
    /// unpremultiply–blend–re-premultiply that keeps antialiased edges from darkening. `.toNearestOrEven`
    /// rather than `.rounded()` because that is the rule Metal's float→unorm8 conversion uses, and a
    /// half-way value rounded the other way is a delta of 1 on a channel that should have been exact.
    ///
    /// **One call to the blend per pixel, not one per channel — this is §7 Tier 2's trap, met.** Before
    /// Tier 2 this loop called `handRolledChannel` three times, once per channel, because every
    /// hand-rolled mode was separable and a channel's blended value depended on nothing but that same
    /// channel of `cb`/`cs`. Hue, Saturation, Color and Luminosity break that: the blended value of
    /// the red channel depends on green and blue too (`Lum`/`Sat` read all three), so the loop now
    /// builds the whole `(cb, cs)` triple first and asks `isNonSeparable` which one function can
    /// answer for all three channels at once. `Composite.metal` never had this problem — its
    /// `blendChannels` already takes a `float3` — which is exactly why the trap is CPU-only.
    private static func drawHandRolled(_ image: UIImage, mode: BlendMode, opacity: Double,
                                       in bounds: CGRect, context: UIGraphicsImageRendererContext) {
        let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
        guard width > 0, height > 0,
              let sourceImage = image.cgImage,
              let backdropImage = context.currentImage.cgImage,
              var source = premultipliedBytes(sourceImage, width: width, height: height),
              let backdrop = premultipliedBytes(backdropImage, width: width, height: height)
        else { return }

        let scale = Float(opacity)
        for index in source.indices {
            // Premultiplied, so opacity scales all four channels — the same `layer.read(gid) *
            // opacity` the kernel does, and for the reason `Composite.metal`'s header gives.
            source[index] = UInt8((Float(source[index]) * scale).rounded(.toNearestOrEven))
        }

        let nonSeparable = mode.isNonSeparable
        var result = backdrop
        for pixel in stride(from: 0, to: source.count, by: 4) {
            let sa = Float(source[pixel + 3]) / 255, da = Float(backdrop[pixel + 3]) / 255
            guard sa > 0 else { continue }  // a transparent source is the identity, exactly

            let sp = (Float(source[pixel]) / 255, Float(source[pixel + 1]) / 255, Float(source[pixel + 2]) / 255)
            let dp = (Float(backdrop[pixel]) / 255, Float(backdrop[pixel + 1]) / 255, Float(backdrop[pixel + 2]) / 255)
            let cs = (min(max(sp.0 / sa, 0), 1), min(max(sp.1 / sa, 0), 1), min(max(sp.2 / sa, 0), 1))
            let cb = da > 0 ? (min(max(dp.0 / da, 0), 1), min(max(dp.1 / da, 0), 1), min(max(dp.2 / da, 0), 1))
                            : (Float(0), Float(0), Float(0))
            // Non-separable modes need `handRolledTriple`'s single call over all three channels;
            // separable ones still go through `handRolledChannel`, once per channel, unchanged from
            // before Tier 2 — `mode.isNonSeparable` picked once per pixel rather than per channel is
            // just hoisting a loop-invariant, not a behaviour change.
            let blended: (Float, Float, Float) = nonSeparable
                ? mode.handRolledTriple(backdrop: cb, source: cs)
                : (mode.handRolledChannel(backdrop: cb.0, source: cs.0),
                   mode.handRolledChannel(backdrop: cb.1, source: cs.1),
                   mode.handRolledChannel(backdrop: cb.2, source: cs.2))

            // (1 - da) * cs + da * blended, then source-over — the same two lines `blendOver` in
            // `Composite.metal` runs, written three times because this array holds `UInt8`es rather
            // than a vector type.
            let channelValues: [(dp: Float, cs: Float, blended: Float)] =
                [(dp.0, cs.0, blended.0), (dp.1, cs.1, blended.1), (dp.2, cs.2, blended.2)]
            for channel in 0..<3 {
                let cr = channelValues[channel].cs + (channelValues[channel].blended - channelValues[channel].cs) * da
                let out = channelValues[channel].dp * (1 - sa) + sa * cr
                result[pixel + channel] = UInt8((min(max(out, 0), 1) * 255).rounded(.toNearestOrEven))
            }
            let outAlpha = da * (1 - sa) + sa
            result[pixel + 3] = UInt8((min(max(outAlpha, 0), 1) * 255).rounded(.toNearestOrEven))
        }

        guard let blended = makeImage(fromPremultiplied: result, width: width, height: height) else { return }
        // `.copy` rather than `.normal`: this image *is* the finished composite of everything drawn
        // so far, so it replaces the context rather than compositing onto it a second time.
        UIImage(cgImage: blended, scale: 1, orientation: .up).draw(in: bounds, blendMode: .copy, alpha: 1)
    }

    /// `image` redrawn into a buffer of exactly the app's byte layout — device RGB, premultiplied
    /// last, 8 bits per component, row 0 at the top.
    ///
    /// Redrawn rather than read out of whatever backing store the `CGImage` arrived with, which for
    /// something out of `UIGraphicsImageRenderer` may be a different component order, a different
    /// bit depth, or an extended range. `MetalCompositor.upload` normalises the same way for the same
    /// reason, and the two agreeing on this conversion is half of why the backends can be compared
    /// byte for byte at all.
    ///
    /// Shared with `MaskResolver` rather than copied there — a mask is resolved and applied in this
    /// same byte layout, and a second spelling of the conversion would be the drift §1 objects to.
    static func premultipliedBytes(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    static func makeImage(fromPremultiplied bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
