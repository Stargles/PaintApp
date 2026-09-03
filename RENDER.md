# Rendering — the background baker and export

TODO item (29). **§2 is owner rulings; read them rather than re-deriving them.** §3 onward is the design and
the build order.

## 0. What is already true

- **There is no export feature of any kind.** No share, file-export or photo-library API is reached from
  app code. The word "Export" reaches the artist only as reassurance copy under the Render Resolution knob
  (`Views/ActionsMenu.swift`, `renderResolutionControl`).
- `Compositor.composite(_:) -> CGImage?` (`Engine/Compositor.swift`) is pure and headless — it runs in the
  logic test tier with no view — and `makeRenderRequest` is frame-parametric. What is missing is a driver
  loop, an encoder and a destination, not a renderer.
- **Compositing already runs off the main thread**: `Compositor.composite` runs on `CanvasView.sandwichQueue`
  (`Views/CanvasView.swift:1469`, `:1514-1516`) and is pure over a `RenderRequest` that holds no live model
  object. What runs on main is everything that *feeds* it — see §3.1.
- **Nothing propagates a content version to an ancestor and frame-scoped invalidation does not exist.**
  LAYER_COMPOSITING §9.1 describes both as built; `RenderTree.swift:116-118` records the rejection of the
  first, and no code inverts `Cel.startFrame`/`frameCount` into a frame → dirty map for the second. The
  invalidation signal today is whole-tree structural equality, recomputed every SwiftUI pass.
- **A hold is one `Cel` spanning `frameCount` frames**, so `LayerContentVersion` is byte-identical at every
  frame of it. Holds dedupe for free the moment `frame` is left out of the key (§4).
- `CompositorBudget.textureBudgetBytes` is `physicalMemory / 16` — MEASURED **183.7 MB** on the owner's
  3 GB iPad 9, where the `3 << 30 / 16` arithmetic the docs used to write reads 192. It chooses a **strip
  height** (§3.8) and never a smaller canvas, because §2.12 forbids answering the knob with less than it asked
  for.
- One raw frame at 2048² is 16.8 MB; ten seconds at 24 fps is 4 GB. Baked frames must be compressed on disk,
  never held as raw textures.
- Composited playback already misses 24 fps on the owner's iPad with no in-betweens present: a six-layer
  sandwich rebuild at 2048² is MEASURED 54.8 ms against a 41.6 ms budget (PERFORMANCE §2 item 5).
- Two earlier designs describe parts of this cache and are superseded by this file: LAYER_COMPOSITING §9.2
  (sequencer-scoped priority queue with a disk LRU) and KEYFRAMES §4.6 (one keyframe span, eager and
  complete, ruled in KEYFRAMES §2.19-20). KEYFRAMES §2.25 lets a derived frame cost more than 1/24 s
  *because* this prebake exists; dropping this item takes that permission with it.

## 1. The ask, in the owner's words

> "rendering: add the ability to export animations as video or a frame as image"

> "the ipad does not have much memory, so I want the paint program to not use much by storing as many things
> it can to disk. Probably the current active cel is the only thing required to be in memory. The paint
> program automatically pulls unbaked frames from disk (layers, compositing, etc), bakes the compositing and
> stores it back straight to disk, so that when the play is pressed it can be played at 24fps. This way, the
> program doesn't run out of memory even with a hundred layers and a thousand cels. The memory is dynamically
> allocated: lets say we have layers 1 through 10 and the program has only enough memory for 3: the three
> bottom layers are pulled, composited and stored, then the next are pulled etc."

> "The render feature consists of two parts: 1) automatic background rendering and baking. 2) export. The
> background renderer will pretty much replace the behaviour of the current compositor, which at the moment
> renders on the main thread live. This means that on large canvases with many layers, it cannot keep up at
> 24fps. This is why the rendering will be on a background thread, so your UX thread runs smoothly for the
> user, and the background thread automatically renders and stores the frames to disk. This should be smart,
> it only rebakes and stores the frames which matter. When you click on play, it pulls the prerendered frames
> so you get smooth 24fps even with a 30+ layers and complex compositing. The method how it renders should be
> sort of like this: It first pulls the bottom layers that fit in memory, then composite bakes them. Then it
> discards them and pulls the next layers and continues compositing them over the prebaked render. Note: this
> isnt a linear thing, as the compositor is a tree. For exporting, since all the frames are already baked and
> stored into disk, all it has to do is make a video out of them, or export one frame as an image."

> "The goal is this: I want to be able to have an animation with tens to hundreds of layers and thousands of
> cels, and when I click the play button, it plays the animation at 24fps. This should not interfere with the
> FPS of the user interface; there should be no lagspikes."

> "I eventually want to make it android and windows compatible so dynamic allocation of some sort may be nice."

## 2. Rulings

1. **Two parts, one store.** A background baker that composites frames to disk, and an export that reads
   those files. Export re-renders nothing.
2. **The baker replaces live compositing.** The main thread never composites. It handles input, the
   timeline, and draws the live stroke over an already-finished picture.
3. **Only the frames that matter are rebaked.** *"When something is modified, only the modified frames are
   rebaked."*
4. **Compositing is chunked bottom-up under a memory ceiling, and the chunking follows the tree**, not a flat
   layer index. Pull what fits, composite it, discard it, continue over the accumulated result.
5. **The goal is the acceptance test.** Tens to hundreds of layers, thousands of cels, 24 fps on play, and
   the UI frame rate untouched.
6. **Portable.** No budget hard-coded to an iPad and no eviction that only iOS can signal.
7. **Container and codec are the session's decision**, not the owner's. See §3.
8. **Export resolution is the Render Resolution knob's value.** The owner expects a compression method that
   exploits flat colour and frames that do not change: *"remember that this is an anime animator, which has a
   lot of flat colors and frames that dont change."*
9. **One renderer serves both playback and export.** Slow is acceptable on heavy compositing. If resolution
   or quality-versus-speed ever forces a separate export renderer, say so and proceed.
10. **Playback may be visibly stale while the bake catches up.** The frame the artist is on is baked first if
    it is not baked yet, so they can keep drawing.
11. **The bake is dumped between launches by default**, with an option in the export menu to store it in the
    project's folder.
12. **The knob is the truth.** *"If the user slides the slider to full, then the canvas should be set to
    full."* Nothing may silently render below the knob's resolution.
13. **A canvas that shows the previous composite for a split second after pen-up is acceptable**, provided
    the main thread never freezes: the artist must be able to move the canvas and lay the next stroke in
    that interval.
14. **Memory correctness is in scope.** *"I want to see if there are any previous memory allocation things in
    this program which are not built correctly."*
15. **The baker replaces, it does not sit beside.** *"I want the code architecture to be very clean and
    non-redundant, with no peculiarities, and no legacy code left by the previous functionality."* When a stage
    lands, the path it supersedes is deleted in the same change — no vestigial parameter, no half-live control, no
    comment describing what used to be here.
16. **"Only the frames which matter" means exactly the frames a change reaches.** *"If I had frame 1 through 10
    and I edited something inside a cel which spanned frames 2 to 6, then only frames 2 to 6 would need to get
    re-rendered. Same with effects, blend modes, and everything related to compositing."* §3.3 and §3.6 are the
    mechanism; §3.3's key is the proof, because a frame the change does not reach has the same key it had.

## 3. Design

### 3.1 What the main thread does, and the pen-up cost this design removed

The compositor is not the freeze. **The table below is the pen-up cost as it stood before stage 2 and is
what the stages after it took off the main thread** — it is here as the evidence the design was shaped
by, not as a description of the running app; the paragraph after it is the present state. At pen-up the
main thread ran, in order (`Views/Canvas/StrokeCanvasView.swift:919-996`, `Views/CanvasView.swift:363-392`):

| step | where | scales with |
|---|---|---|
| re-rasterise the whole cel — every dab of every stroke — into a fresh canvas-sized bitmap | `StrokeCanvasView.swift:986` → `Engine/VectorLayer.swift:3016` | canvas area × dabs on the cel |
| the snapshot: `renderSources` flattens **every visible leaf** to a canvas-sized `CGImage`, fanned over cores but blocking the caller | `Engine/RenderRequest.swift:883-995`, `Services/PixelOps.swift:45-59` | canvas area × layer count |
| Core Animation converts three `premultipliedLast` RGBA composites to its native BGRA inside the commit | `CanvasView.swift:1531-1535`; BUGS.md "a hitch per stroke-lift" | canvas area × 3 |
| the live mask resolve, `RenderSizing.liveComposite` | `CanvasView.swift`, `liveMaskStrokeBegan` | render size × layers, masked documents |
| 400 ms later: the thumbnail flattens the cel into `celThumbnailRasterBound`, downsamples to 120 px, then publishes a second whole SwiftUI pass | `Models/CanvasManager.swift`, `celThumbnailImage` | bounded, then one SwiftUI pass |

**Those last two used to thrash the flatten memo and no longer do**, which is worth stating because it is the one
figure in this section that moved rather than merely being described. `RasterizeKey` carries width and height
(`PixelOps.swift:156-157`), so the sandwich at its reduced size and a *native* thumbnail minted separate canvas-sized
entries per cel in one 192 MiB memo — six layers at 4096² needing 201 MiB reduced plus 384 MiB native, so the memo
never held one frame and every rebuild was cold. At 2048x1024 the same six entries are 48 MiB and everything hit,
which is why the freeze read as a large-canvas symptom. Both consumers are now bounded, and the live mask resolves at
the sandwich's own size rather than a second one.

**After this design the main thread does exactly four things**: handle input and draw the live stroke scratch; mutate
the model and publish; mint a `FrameRecipe` on request (§3.2) in O(layers) with no pixel work; and put finished
images on screen. Nothing on it is proportional to canvas area.

### 3.2 The recipe — how pixel work leaves the main actor without a race

The model is `@MainActor`. The baker must not read it mid-edit, and copying every cel's pixels to hand over (what
`ProjectStore.SaveSnapshot` does, `Services/ProjectStore.swift:134-305`) is the cost we are removing. The seam is
that the expensive state is already copy-on-write: a vector cel's `_elements` is an array, and a raster cel's
`CGContext.makeImage()` is a copy-on-write snapshot until the next stamp.

A **`FrameRecipe`** is minted on the main actor for one frame in O(layers): the `[RenderNode]` tree at that frame,
and for each visible leaf a **`LeafSnapshot`** — the cel's `LayerContentVersion` plus the immutable values its render
needs (the element array, transform and size for a vector tier; the `makeImage()` snapshot for a raster tier; the
`DerivedCelContent` render thunk for an in-between). Minting touches no pixels. The baker renders leaves from
snapshots on its own queue through a static render entry that takes values rather than a live `VectorCanvas`. The
`PixelOps.rasterizeCache` memo stays in front of it, keyed as today, so a cel unchanged since the last frame is not
re-flattened.

### 3.3 The bake key

One key names the pixels of a frame: `FrameBakeKey` (`Engine/FrameBakeKey.swift`), built from a `FrameRecipe`,
carrying everything the live canvas's own `SandwichKey` compares **with `frame` removed** and three inputs no
in-memory cache carries:

- the resolved tree (`[RenderNode]`: structure, opacity, visibility, blend mode, isolation, masks including the
  implicit clip-to-below mask, each node's effect resolved at the frame — a **folder's** grade is resolved here
  because no `LayerContentVersion` carries it);
- every leaf's `LayerContentVersion`, which already includes the effect resolved at the frame and the
  `DerivedCelContent.identity` of an in-between;
- the mask source stacks;
- render size, `RenderResolution`, `RenderQuality`, paper colour, paper visibility and canvas padding;
- **`AlphaMask.tuningGeneration`**, **`Compositor.backend`** (both accessors over a lock — §4), and a
  **store format version** — a persistent store must carry what a
  process-lifetime cache could ignore.

`frame` affects no pixel: the compositor reads it only to rebuild sub-requests (`Compositor.swift:1039`,
`Engine/MaskResolver.swift:179`). Leaving it out is what makes a nine-frame hold one file. It is safe only while the
tree and the leaf versions capture every frame-dependent input, which is why the folder grade is in the tree and why a
future pose must be a `DerivedCelContent` whose identity includes the frame (KEYFRAMES §8).

**A stale file can never be shown as fresh.** The display path computes the current frame's key to find its file; a
key with no file shows the previous picture (§2.10) and asks the scheduler for that frame first. Dirty marking (§3.6) is
a scheduling hint, never the truth.

### 3.4 Chunked compositing — the owner's method, shaped to the tree

Both compositor backends are already a bottom-up single-accumulator walk (`Engine/Compositor.swift:735-864`,
`Engine/MetalCompositor.swift:632-823`). `blendOver` reads the backdrop only from the accumulator and the source only
from the layer (`Engine/Composite.metal:236-250`); the six non-separable modes, Add, Subtract and Linear Light are pure
functions of those two (`Compositor.swift:499-580`); every neighbourhood kernel samples the accumulator. **No blend mode
and no effect reads a layer above it.** The walk already quantises to 8 bits per step, and a readback-then-upload round
trip is lossless (both sides `deviceRGB` premultiplied-last at the same size). So cutting the walk into chunks and
carrying the accumulator across the cut is **exact**, with four rules:

1. **The chunk unit is a node, not a layer index.** A node with `needsOwnBuffer` (`Models/RenderTree.swift:219-235`:
   a folder at opacity ≠ 1, a blending mode, a mask, a grade, `.mix`, isolation over a blend) starts from transparency
   and blends in as one unit. Never cut inside it; if it alone exceeds the budget, chunk *its* children into its own
   transparent accumulator and recurse.
2. **A `.stack` folder is transparent to chunking** — it recurses onto the caller's accumulator
   (`MetalCompositor.swift:762-772`).
3. **Ink-input effects pin sources.** Outline always, and Bloom by default, re-walk `tree.split(atLeaf:).below` from
   the leaf sources to build an ink-only, paper-free input (`MetalCompositor.swift:656-679`,
   `Compositor.swift:1031-1059`; EFFECT_BACKDROP §3). A chunk that discarded those sources cannot rebuild it. When the
   root walk contains an ink-input node, the baker carries a **second accumulator without paper** alongside the first
   (EFFECT_BACKDROP §3 option C); inside a buffered scope the input degrades to backdrop already, so the rule is
   root-only.
4. **Masks are resolved before the walk.** A mask's source stack may name a layer anywhere in the document, including
   above the masked node (`RenderRequest.swift:352-355`, `MaskResolver.swift:176-181`). Coverage is 1 byte per pixel
   and already cached; resolving every mask first, from its own small source subset, releases the constraint.

The accumulator crosses a chunk boundary as a **synthetic leaf**: chunk k's `RenderRequest` is
[accumulator, chunk nodes…], so `Compositor.composite` needs no new mode.
`renderSources` gains a leaf-subset parameter; that is the only change to the snapshot.

**Built 2026-09-02 (stage 3), and three details of the paragraph above came out differently.**
`Engine/ChunkedComposite.swift` is the driver; `RenderRequest.ChunkContinuation` is the two lines each
backend gained.

- **`background: nil` for k > 0 is wrong, and it is rule 3 that says so.** The paper still has to reach a
  continuation chunk, because `gradedInkOverPaper` lays it back down under the graded ink — so the field
  keeps the frame's paper for *every* chunk and the continuation suppresses only the *fill* at the top of
  the walk. `paperInBackdrop` is then `background != nil` unchanged in both backends, which is what keeps
  an `.ink` effect live across a cut at all; had `background` gone nil, the re-walk would have silently
  not happened and the effect would have graded the paper-bearing accumulator. Metal needs one extra line
  the CPU does not: `UIGraphicsImageRenderer` starts transparent, a pooled texture holds the last frame.
- **The width is `N = budget/textureBytes(renderSize) − carried − peakCompositeTextures`**, counted in
  *leaf sources* rather than nodes. `peakCompositeTextures` is already `2 + depth-pairs + ≤2 effect
  intermediates` — it counts the root accumulator pair itself — so the `2 +` in the sentence above was
  double-counted; `carried` is 2, the accumulator and its paper-free twin. **Masks are not a separate
  term**: rule 4 puts a mask's source leaves *inside* N, which is stricter than costing the coverage at
  1 B/px, because the canvas-sized source it resolves *from* is four times the coverage it resolves *to*.
- **One backend for the whole frame.** `Compositor.composite` resolves `.automatic` from
  `request.tree.prefersGPUCompositing`, and a chunk's tree is not the frame's — a hundred-leaf document
  prefers Metal while two-leaf chunks of it prefer CoreGraphics, and the two agree only to within a
  channel step on the blend modes. So `Compositor.composite(_:resolving:)` takes the answer as an
  argument and the driver asks the whole tree once. A frame can still mix backends: a `.metal` chunk that
  comes back `.unavailable` falls back to CoreGraphics for that chunk alone, exactly as before. That is a
  property of the device rather than of where the boundary fell, and it is the same fallback every
  composite in the app has always had.

**Stage 3 shipped verified on CoreGraphics only; the Metal half was closed 2026-09-02 and the two
Metal-specific lines are now pinned.** `ChunkedCompositeLogicTests` forces `.coreGraphics` on every
run, so neither the continuation's texture clear nor Metal's own copy of `substitutingChunkAccumulator`
had a test on it. `ChunkedCompositeMetalLogicTests` is the same shape with the backend forced the other
way — MEASURED, 11 tests, **0 skipped**, on the iOS 26.5 simulator.

- **Metal-chunked is byte-identical to Metal-unchunked, with no tolerance.** The channel-step tolerance
  `CompositorParityLogicTests` carries is about the two *backends* disagreeing and is not this claim:
  same backend on both sides means same rounding and same blend arithmetic, so the only variable is
  where the walk was cut and the gate is exact. It held on the zoo at widths 1, 2, 3, 5, 8 and 40, with
  and without paper, padded and unpadded.
- **The reference must go through `MetalCompositor.attempt`, not `Compositor.composite`.**
  `resolving: .metal` falls back to CoreGraphics *silently* when there is no metallib, so a suite that
  merely forced `.metal` would agree with itself perfectly while measuring nothing — the banner-versus-count
  trap with a backend in place of a test count. `attempt` returns `.unavailable` instead, and the suite
  asserts it did not.
- **The missing-clear defect is visible in one band only, which is why a test for it has to be built
  rather than assumed.** The stale texture a continuation inherits is an *earlier accumulator of the same
  frame*, so its coverage is a subset of the current one's: where the accumulator is opaque, source-over
  hides the stale pixels exactly, and where it is transparent the stale pixels are transparent too. Only
  **partial** alpha shows the difference. So a fixture reaches it only with no paper (or translucent
  paper), **translucent ink**, and **at least two draws in the chunk before the cut** — `over` writes into
  `back` and swaps, and `attempt` releases `front` then `back`, so the next chunk's `acquire` pops the
  accumulator one draw before the end; one draw per chunk leaves that texture holding the pre-composite
  clear, which is zero. MEASURED with the clear deleted: three tests red, `RGBA(192, 0, 0, 192)` against
  `RGBA(128, 0, 0, 128)` — 0.5 ink composited over a stale 0.5 is 0.75. The six tests with paper on stayed
  green, and so did the padded-canvas one: a padded margin is transparent in *every* accumulator state,
  so there is nothing stale there to show.
- **Rule 3's Metal copy is pinned by the same fixtures as the CPU's.** MEASURED with
  `.substitutingChunkAccumulator(of: request)` dropped from the `.ink` fork: eight test cases red, the
  legible one being `RGBA(255, 255, 255, 255)` where `RGBA(0, 0, 0, 255)` belongs — paper white in place
  of the black outline, i.e. the silhouette gone rather than a number shifted.

Nothing was found that the chunking gets wrong on Metal but right on CoreGraphics.

The compositor's own intermediates were never the problem: `peakCompositeTextures` (`RenderTree.swift:543-552`) is
2 for a flat stack of any length and grows with depth. The problem is `sources`, one canvas per visible leaf, all
live at once — 840 MB for 100 leaves at 2048x1024 against a 192 MiB budget. Chunking the snapshot is the whole win.

### 3.5 The store

`FrameBakeStore` is the app's first on-disk derived store. One file per bake key, content-addressed by the key's hash,
under `Library/Caches/PaintApp/bakes/<projectID>/<resolution>/`. Deleted at launch (§2.11) unless the artist chose to
keep it, in which case it lives in `Documents/Projects/<Name>.paintbake/` beside the package — never inside it,
because every save rebuilds the package through a staging directory and `validateProject` gates the swap on
manifest-named files (`ProjectStore.swift:545-634`).

**Format (§2.7, decided): lossless, one frame per file, BGRA premultiplied rows compressed with LZ4** through Apple's
`Compression` framework (`COMPRESSION_LZ4`), a 32-byte header carrying width, height, bytes-per-row, format version
and the key hash. Reasons: LZ4 decodes at gigabytes a second, so an 8 MiB frame is single-digit milliseconds on the
device; flat colour is runs, which LZ4 encodes as matches, so the anime ratio is expected high (MEASURE it on the
owner's "UI Test" document before trusting a number); content addressing stores a hold once; every frame is
independent so scrubbing backwards costs what forwards costs; the format is portable to any platform with an LZ4
decoder, which is all of them; and it is exact, which the live canvas at rest requires. BGRA premultiplied-first is
what Core Animation wants, so the convert that costs a hitch per stroke-lift today happens once, off-main, at bake
time — which also means `CompositorMetalEngine.readBack` should render into `bgra8Unorm` (BUGS.md already scopes
that as a one-capability-check change). If the ratio on real documents disappoints, the next step is a per-row Up
filter before LZ4, not a video codec.

**Built 2026-09-02 (stage 4a): `Engine/FrameBakeKey.swift` and `Engine/FrameBakeStore.swift`, headless.**
Three things in the two sections above came out differently.

- **The header is 64 bytes, not 32.** A SHA-256 digest alone fills 32, so the original number left no room
  for the width, height, stride, the two sizes and the flags the same sentence asked for. Little-endian:
  magic `PBK1` (0), format version (4), flags (6, bit 0 = LZ4 payload), width (8), height (12),
  bytes-per-row (16), uncompressed bytes (20), compressed bytes (24), reserved zero (28), digest (32..64).
  Rows are **tightly packed** — `bytesPerRow == width * 4` whatever CoreGraphics chose — so the ratio does
  not depend on a platform's own alignment (§2.6).
- **`COMPRESSION_LZ4_RAW`, not `COMPRESSION_LZ4`**, and §3.5's own reasoning is what says so. Apple's
  `COMPRESSION_LZ4` wraps the stream in `bv41` block framing that no other LZ4 decoder reads, which
  contradicts "portable to any platform with an LZ4 decoder". `_RAW` is the standard raw block; its one
  extra requirement is knowing the uncompressed size before decoding, and the header already carries it.
  If the encoder does not shrink a frame the payload is stored raw with the flag clear, so a file is never
  larger than its pixels plus one header.
- **MEASURED ratios, headless on the iOS 26.5 simulator** — the number §3.5 asked to be measured rather
  than expected, though the owner's own "UI Test" document on the device is still owed. A 512² synthetic
  flat-colour frame (three filled rects on a flat ground) is **1,048,576 B → 9,658 B, 108.6x**. The same
  size in seeded noise is **1,048,576 B → 1,048,576 B, 1.00x**, i.e. it takes the raw branch. So the anime
  expectation holds at the extreme and the fallback is reachable, which is what makes both branches
  testable.

**Measured again 2026-09-02 (stage 4e), on artwork rather than on a rect — it confirms one sentence of
this section, refutes another outright, supplies a third the section never wrote, and puts a number on
what stage 4c bought.** The full tables are PERFORMANCE §10; what belongs here is what they change. The
fixtures are the document §2.8 names: flat cel art (six colours in large hard-edged polygons with real
vector ink stamped over them), a hold (three strokes on transparency), a painted gradient as the honest
pessimistic bound, and seeded noise as the theatrical one. **Byte counts are exact and
build-independent — the simulator and all three device runs agreed to the byte. The milliseconds are the
owner's iPad 9 in Release**, taken on both sides of 4c's deletion, and the Debug simulator run that
preceded them got the *split* backwards, which PERFORMANCE §10.2 keeps as a warning rather than as data.

- **The ratio is high and *rises* with canvas size.** Cel art is **54.4x at 2048x1024, 66.9x at 2048²,
  73.2x at 4096²**; a hold is **135-155x**. A bigger canvas draws the same picture with more flat pixels
  in it, so the incompressible part — the ink's antialiased edges — is a shrinking share. Ten seconds of
  cel art at the owner's canvas is **37 MB**, so the store's 512 MiB ceiling holds about an hour of it
  before §3.3's content addressing is even counted. **The bound that matters is not the noise row, it is
  the painted one at 1.49x**: a smooth gradient has no exact byte repeat and barely compresses at all.
- **"Single-digit milliseconds on the device" is confirmed with room to spare: an 8 MiB frame is
  1.5-3.1 ms** on the store as it stands after stage 4c (it was 4.0-5.0 before it — see below). The cold
  `F_NOCACHE` storage read inside that is **0.1 ms**, because a 154 kB file is off the NAND before it
  has started; only the incompressible fixtures, whose files *are* the frame, pay a measurable read.
- **Decode is proportional to the frame's *pixels*, not to its file, and it is the finding here that no
  change has touched.** A hold is a *quarter* of cel art's file and decodes **slower** at every size, in
  every run: 3.1 vs 1.5 ms at 2048x1024, **24.6 vs 9.9** at 4096². LZ4 rebuilds the same buffer either
  way and a nearly-empty frame is long small-offset matches, every LZ4 decoder's slowest path. **So the
  ring's "byte budget rather than a count" below has to mean *decoded* bytes** — and the frames content
  addressing makes cheapest on disk are the dearest to play, which is the opposite of the intuition this
  section was written with.
- **Every size now fits a play interval and the worst case has real headroom: 24.6 ms against 41.6,
  1.70x**; at the owner's 2048x1024 it is 1.5-3.1 ms. **Before stage 4c the same worst case was 39.3-39.8
  ms — 1.05x**, i.e. 96% of the interval to get one frame on screen. Play still must not decode on the
  tick, which is what the ring below is for; what is new is that a one-frame lead is now enough.
- **Stage 4c's copy elimination is measured on both sides of it, and it is worth 1.6-2.8x on the whole
  decode.** The old `load(_:) -> CGImage?` decompressed into a `[UInt8]`, copied it again so a
  `CGContext` could own the buffer, then `makeImage()`d a third: **1.6-2.6 ms of `CGImage` build against
  the LZ4's 1.3-1.4** at 2048x1024, and 15.3-21.5 against 12.9-13.2 at 4096² — larger, at every size,
  than the codec it sat behind. `DecodedFrame.makeImage()` measures **0.0 ms at every size** — and that
  is the *eager* copy going away, not a claim about the display: both spellings produce a deferred
  `CGImage`, and the pixels reach Core Animation at composite time in either. Two cautions for whoever
  finds the next one of these: it was invisible in Debug, where that column read as 8% of the decode
  against the codec's 91%; and it only ever showed up because the decode was measured *split* rather
  than as a total.
- **The encode, which this section never mentions, is 5-13 ms a frame at 2048x1024 and 25-31 ms at
  4096².** The BGRA convert inside it is 1.2-2.4 ms at the owner's canvas and 12.7-13.8 at 4096² — so the
  `readBack`-into-`bgra8Unorm` change named in the paragraph above is worth a fraction of the bake where
  the owner draws and about half at the knob's maximum, not the 2x a Debug run implied. Still worth
  having; it also deletes the per-stroke-lift hitch BUGS.md attributes to the same convert.
- **The last sentence of the paragraph above is refuted, not deferred.** A per-row Up filter before LZ4
  makes **every fixture bigger** — cel art +39%, a hold +28%, painted +2.5% — and a Sub filter also
  loses everywhere (+8%, +3%, +1.2%). A filter helps a coder that models smooth variation, and LZ4
  matches exact byte sequences instead: a flat region is already one long match, so differencing it to
  zeros codes to the same size, while every hard edge becomes a band of residuals that differ row by row
  where the source rows were byte-identical. The loss is largest exactly where this document has the most
  edges. And the cost is not a rounding error — it is the whole decode over again: the filter is
  **4.3-7.1 ms** on the way in and **4.4-8.9 ms** on the way out at 2048x1024, against a 1.5 ms decode.
  Adopting it would have multiplied the decode by four to make the file 39% bigger. If the ratio ever does disappoint, reach for a coder that models
  prediction error at all — not a filter in front of a match-only one.

**The key is §3.3's field list with no `frame`, built from a `FrameRecipe` by a hand-written canonical byte
encoder rather than from any `Hashable`, and that is not fastidiousness.**
`LayerContentVersion.hash(into:)` deliberately omits `effect` — correctly, since every in-memory cache in
this app compares `==` after the bucket lookup, so a collision costs one compare. A content-addressed
store has no second chance: the filename *is* the digest, so a missing field is the wrong picture served
with no error. `InterpolatedCelIdentity.hash(into:)` omits four more fields for the same reason, and it
reaches the key through `LayerContentVersion.derived`. The encoder therefore emits a discriminator byte
per enum case and a length prefix per collection, writes floats by `bitPattern`, and carries **no
`default:` clause anywhere** — so a fourteenth `Effect` case or a twenty-seventh `BlendMode` is a compile
error in `FrameBakeKey.swift` rather than a silent collision on disk. That is the durable half of the
guarantee; `FrameBakeKeyLogicTests` is the other half, one row per field.

**Two things `FrameRecipe` already folds in, and one it does not.** `canvasSize` is a `RenderSizing`
already applied and rounded, so it is the real buffer; and **canvas padding needs no field of its own**,
because `CanvasManager.canvasSize` includes the margin and the margin's only route into a composited pixel
is `RenderBackground.rect`, which `canvasBackground(renderedInto:)` insets by it — with the paper hidden
the padding reaches nothing at all. **`RenderResolution` is *not* implied by `canvasSize`** and is a
separate field: `RenderSizing.native` ignores the knob outright, so all three positions mint one buffer,
and under `.liveComposite` two positions can round to one size on a small enough canvas.

**A kept bake needs a stable stamp.** The process-lifetime key uses object identity and in-memory version counters
(`RasterLayerTexture.version`, `VectorCanvas.version`), which restart at every open. A bake the artist keeps beside
the project must key on something the document persists — a per-cel content stamp saved in the manifest and bumped
on every edit, or a hash of the cel's encoded tiers. Stage 6 decides which; stage 4 does not need it because the
default store dies with the process.

A small **decoded ring** holds the frames just ahead of the playhead, under a byte budget rather than a count. Play
never decodes on the display thread: the scheduler decodes ahead into the ring and the tick reads from it. **The
bake loop alone cannot do that** — it only rings frames it visits, and playback dirties nothing — so
`FrameBaker.fillRingAhead` (stage 4d) tops the window up from `keyByFrame` when the queue drains, walking outward
only, because the ring is routinely narrower than the lookahead and a rescan would churn forever.

**The read path is `store.loadDecoded(key) -> DecodedFrame?` → `ring.insert` → `.makeImage()`, and there is no
second spelling beside it (stage 4c).** `load(_:) -> CGImage?` and `FrameBakeStore.image(fromBGRA:)` are
*deleted*, not kept: that path decoded into a `[UInt8]`, built a `CGContext` over it and called `makeImage()`,
which is a second canvas-sized copy and a re-encode of bytes that were already exactly what Core Animation
wants — and a store answering in `CGImage` could not fill the ring at all without decoding twice.
`decompress` returns `Data` for the same reason: `DecodedFrame` holds `Data` so `makeImage()` can hand the
same allocation to a `CGDataProvider`, and an `Array` → `Data` copy in between is 16.8 MB moved per frame at
2048², at 24 fps, for nothing.

**Disk full** is a bake failure, not a document failure: the store stops writing, drops files farthest from the
playhead, and playback falls back to stale frames (§2.10). The document is untouched.

### 3.6 The scheduler

One serial baker owns a priority queue of frames. Order: the frame the artist is on (§2.10); then frames ahead of
the playhead in the play direction; then outward from the playhead; then nothing. Dirty marking is cheap and coarse
on the main actor — a cel edit dirties `[startFrame, endFrame)` of that cel's layer; an in-between whose
`InterpolatedCelIdentity.references` name the edited cel dirties its own span; a structural edit (order, folder,
mask, blend, effect track) dirties every frame. The exact test is the key (§3.3): a dirty frame whose recomputed
key already has a file costs nothing, which is how a scrub through a hold is free.

The baker produces `full`, which is what the live canvas shows at rest; `below` and `above` — keyed additionally
by the active leaf, transient, never stored — stay on `CanvasView`'s own `sandwichQueue`, so the stroke still sits
between two finished pictures. **This paragraph asked for one worker and wanted one memo, and stage 4d found the
memo is bought by the *size*:** `PixelOps.rasterize` and `MaskResolver.CacheKey` are keyed on the buffer, so the
bake mints at `.liveComposite` and the three share their flattens across two queues. That also lets the halves keep
`.userInitiated` while the bake keeps `.utility`, which is what §2 asks for. 
**This section said the single-slot drop-if-busy behaviour of `isSandwichRebuilding` "is not inherited", and that
sentence was wrong about the thing it was declining to inherit.** `isSandwichRebuilding` is not a drop. It is
mutual exclusion with a retry: `finishSandwichRebuild` ends in `reconcileLayers()`, which re-derives the key from
the model and starts the rebuild the guard declined — the same "waits one iteration rather than evaporating"
contract `FrameBaker.isBaking` was written to provide, reached by coalescing on the latest key instead of by a
queue. So the queue reorders and never discards on *both* sides, and always did.

The flag therefore stays, and deleting it is not available. `sandwichQueue` is **serial**: without the guard every
SwiftUI pass that moves the key queues a rebuild, so a two-second scrub at display rate queues ~120 jobs — each a
`resolve()` plus two composites, roughly 20 s of `.userInitiated` work for pictures nobody will ever see, starving
the bake behind it. What was actually wrong was the *claim*, and it is corrected here rather than worked around.

**Built 2026-09-02 (stage 4c): `Engine/FrameBaker.swift`.** `CanvasView.startSandwichRebuild`'s idiom — a
`@MainActor` owner, a serial `DispatchQueue` at `.utility`, a hop back — with `isBaking` as mutual exclusion
rather than a slot, so a request arriving mid-bake waits one iteration instead of evaporating.

**There is no push funnel that knows a frame, and the paragraph above assumed one.** `beginCanvasEdit()` is a
chokepoint but the wrong one: it runs *before* an edit, to bake pending transients, so it cannot know what the
edit is about to touch. `recordUndo` is documented as *"the shared entry point every call site funnels
through"* and has seventeen — but the undo and redo *closures* it stores do not go through it, so replaying a
step would reach no frame at all. `objectWillChange` fires for tool and brush state that reaches no pixel and
misses the mutation that matters most: a dab lands in `VectorCanvas`/`RasterLayerTexture`, which are classes,
so `@Published var layers` is never written and nothing is published.

The one thing every content edit *does* reach is the tier object's own version counter
(`VectorCanvas.invalidate()`, `RasterLayerTexture`'s four bumps), and `LayerContentVersion` already reads
exactly those. **So the seam is a sweep, not a hook**: `FrameBaker.syncDirty()` compares the document's cel
layout against the layout it last saw and dirties the difference. O(layers + cels) of integer and pointer
comparison with no pixel work, no call site to remember, and it catches undo, redo and every mutation site
that does not exist yet — it is §0's missing *"inversion of `Cel.startFrame`/`frameCount` into a frame →
dirty map"*. Three tiers, and two are coarse on purpose because §3.3 makes over-marking cost one O(layers)
mint and no composite:

1. **Exact.** A cel whose content or span moved dirties **both** its old span and its new one — the frames it
   left show something else now. This is §2.16's tier.
2. **Every frame**, for any structural change, which is this section's own ruling rather than a compromise.
   `StructuralStamp` is `renderTree(atFrame: 0)` — the model's own projection of order, folders, opacity,
   visibility, blend, isolation and masks, already `Equatable` because `SandwichKey` compares whole trees —
   plus the paper, the knob, the scene length, `AlphaMask.tuningGeneration`, `Compositor.backend`, and
   `effectTracks`/`keyframeMarks`. **The probe frame is 0 and fixed**, so scrubbing does not read as a
   structural change; `effectTracks` is what closes the gap that leaves, since a curve moving frame 7 and not
   frame 0 is invisible in the tree at the probe frame.
3. **Every interpolated cel's span**, whenever any cel changed. That is this section's reference rule with the
   reference test dropped, and deliberately: an in-between's picture also moves when its *recipe* changes
   (`t`, spacing, a refitted lattice), `InterpolationRecipe` is `Codable` and not `Equatable`, and a
   hand-written comparison of its fields is exactly the "which field did I forget" hazard a content-addressed
   store punishes with a wrong picture and no error.

**A write failure marks the frame clean, and that is the non-spinning choice.** Leaving it pending would put
the loop in a tight cycle re-compositing a frame it cannot write, for no better picture. The dirty bit is a
hint and this one is spent; the *key* still says truthfully that there is no file, so the read path is a miss
and §2.10's previous picture stays.

### 3.7 Playback

**Done, 2026-09-01 (stage 1).** `CanvasManager` owns `isPlaying` (published), a `PlaybackClock`
(`Engine/PlaybackClock.swift`) and the tick source; `AnimationTimeline` holds no playback state at all and only
calls `togglePlayback()` / `stopPlayback()` and reads `isPlaying`. The frame is derived from elapsed wall time and
spent through `advancePlayback(by:)`, so a late tick skips rather than slows and the clock does not drift; `fps` is
read at derivation time and its `didSet` re-bases the epoch, so a mid-play rate change takes effect without moving
the playhead; the `Timer` runs in `.common` modes, so a scroll or drag no longer stalls playback. Playback stops
from `canvasInteractionBegan()` (a touch about to become an edit), the timeline's `onDisappear`, and any
`scenePhase` away from `.active` — the last is required by the wall clock rather than optional, since a
backgrounded app would otherwise return owing every frame of the time it was away. TODO (28) and KEYFRAMES §5 get
the hoist they needed.

A tick reads the ring, since stage 4d: `currentFrame` publishes, the canvas reconciles, and `updateSandwich` asks
`FrameBaker.image(atFrame:)`, which is the ring then the store then a miss. If the frame is not baked the previous
picture stays (§2.10).

**The timeline's baked-frame indication is done, 2026-09-02 (stage 4f).** `Views/TimelineBakeBar.swift` is the
arithmetic — unbaked runs, the bar's geometry, the string a UI test reads, and the throttle — and
`TimelineBakeBarView` in `TimelineTrackView.swift` is the `UIColor` and the `UIRectFill`, an amber strip overlaying
the ruler's bottom 3 pt. Four things came out differently from what this section said.

- **Ink marks what is *not* baked.** KEYFRAMES §4.6 leans the other way (*"a span is either cached or not and the
  timeline can show it"*) and the polarity was decided against ink rather than against that sentence: the steady
  state of a document at rest is that **every** frame is baked, so marking the baked ones paints a permanent
  full-width band that says nothing and competes with the loop band and the playhead for the same 18 pt. Marking
  the unbaked leaves the ruler clean at rest and the mark shrinks toward nothing, which is a progress reading
  obtained out of the polarity instead of a second mechanism. The ring is deliberately not a third state.
- **`isBaked(atFrame:)` as this section defined it could not serve the consumer this section names.** It was one
  recipe mint and one `stat`, which is right for the one frame the *canvas* asks about and unusable for a ruler:
  a mint is a `LeafSnapshot` per visible leaf, so a 300-frame document is 300 × layers of freezing and
  `makeImage()` **per redraw**, costing more than the bake it describes. It is now
  `!bakeQueue.isPending(frame) && keyByFrame[frame] != nil` — two dictionary lookups, and the baker's own belief
  rather than a fresh statement about the filesystem. **Both halves are load-bearing**: an edit leaves
  `keyByFrame` in place (entries are forgotten only on failure), so the recorded key still names a real file
  holding the picture from *before* the edit, and the dirty bit is the only thing that says so.
- **`onFrameFinished` is a registry, not a slot.** Stage 4d gave the single closure to `CanvasView.Coordinator`
  and the timeline is a second consumer of the same event; two named callbacks would be the peculiarity §2.15
  rules out. `observeFrameFinished(_ owner:_:)` is keyed by owner identity and self-pruning.
- **The bar is refreshed on its own path, not through `TimelineLayoutKey`.** That key is compared on every
  SwiftUI pass and its own rule is *"nothing that moves faster than the layout does"*; a per-frame baked set moves
  once per baked frame. It gets `movePlayhead`'s treatment — called from both sides of the gate — plus the
  callback, because a bake raises no SwiftUI pass at all. **The two halves are asymmetric on purpose**: a frame
  going *unbaked* happens in `syncDirty`, inside a pass, so `relayout` draws it in the same turn; a frame going
  *baked* arrives on the callback and is throttled to ten a second. Alarm is immediate, reassurance settles in.

### 3.8 Full means full

Nothing sizes a composite below the knob. When the native texture set exceeds the budget the baker
composites in **horizontal strips**, each with an apron equal to the summed kernel radius of the effects in the tree,
and writes the strips into one frame. Sources are cropped to the strip plus apron, so the peak is a strip's worth of
textures, and the budget chooses the strip height instead of the resolution.

**Built 2026-09-02 (stage 5). `Engine/StripedComposite.swift` is the driver, and five things came out differently
from the paragraph above.**

- **Strips and chunks nest, strips outside, and the nesting is forced rather than chosen.** A chunk (§3.4) cuts by
  *node* and hands its accumulator to the next chunk **in the same buffer**, so a chunk cannot span two strips. A
  strip cuts by *space* and is a whole self-contained composite of the entire tree over fewer rows. So the strip loop
  is outer and each strip is composited by `ChunkedCompositor` exactly as a whole frame is.
- **There is one budget account and the strip planner does not own it.**
  `ChunkedCompositor.affordableRows(width:tree:budgetBytes:)` is `chunkSources` solved for the height instead of for
  the leaf count, and it lives beside it. The target is *"one leaf still fits"*, not *"every leaf fits"*: the node cut
  is free and the space cut costs an apron in every strip, so the plan takes the **tallest** strip whose buffer still
  affords one leaf and lets chunking absorb the rest. A strip that still does not fit is therefore chunked by the
  existing formula with no special case anywhere.
- **An ink-input effect needs nothing at a strip boundary but the apron, and §3.4 rule 3 does not generalise.** Rule 3
  is dangerous for a chunk because a chunk *discards sources* and the `.ink` re-walk of `tree.split(atLeaf:).below`
  cannot be rebuilt from what the chunk holds. **A strip discards no sources at all** — it windows every one of them
  and hands the whole tree to every strip — so the re-walk inside a strip is the window of the whole frame's re-walk,
  and the apron covers the kernel's own reach past the band. Rule 3's chunk machinery keeps working *inside* a strip
  unchanged, because a chunk boundary is still a chunk boundary there.
- **Two effects read absolute position rather than a neighbourhood, and no apron can pay for them.** `noiseValue`
  hashes the pixel's coordinate and `screenValue` indexes a 4x4 dither screen by `gid.y & 3`, so a strip would
  restart the grain and jump the screen's phase at every seam — a wrong picture with no error. `EffectParams` gained
  `originX`/`originY` (appended at the end, the one position the all-scalar layout rule makes safe), both backends
  stamp it through one `Effect.passes(inFrameAt:)`, and `applyEffect` passes `gid + origin` to the two branches that
  want it while every neighbourhood kernel keeps the local `gid`. `Effect.readsAbsolutePosition` is the list a test
  holds them to.
- **Three memos are keyed on the buffer's *size* and would collide across strips.** A plan's strips are all the same
  size but the last, so `PixelOps.RasterizeKey`, `MaskResolver.CacheKey` and `MetalCompositor`'s `UploadCache.Key`
  each hand strips 1..N whatever strip 0 put there — one band of the drawing repeated down the canvas, on an
  ordinary document with no effect, mask or blend in it. All three carry the window now. **The third was found by
  running the pin on the second backend**: the upload cache has no CoreGraphics counterpart, so
  `StripedCompositeLogicTests` was green on every fixture in the file while the GPU repeated a band.
  `StripedCompositeMetalLogicTests` reds five of its eleven tests without it.

Everything else a strip needs is already spelled "the buffer is smaller", which both backends understood before
strips existed: `canvasSize` is the band, `RenderBackground.rect` is the paper translated into it and clamped by the
fill each backend already does, the sources are the leaves drawn through a translated CTM (`PixelOps.rasterize`
gained a `window`), and masks resolve from those. **Neither backend gained a code path; they gained one uniform.**

**The two mid-stroke sandwich halves were left composing the frame whole, and were then the only
composites in the app a strip did not cover** — fixed 2026-09-02, one commit after stage 5.
`CanvasView.startSandwichRebuild` called `Compositor.composite` on `below` and `above` directly, so on
a document over the budget both reached `MetalCompositor.attempt`'s `guard wanted <= budget`, came back
`.unavailable`, and fell to `CoreGraphicsCompositor` **for the duration of every stroke** — drawing on
exactly the documents §3.8 exists to serve got *worse* than before stage 5, a shrunk frame on the GPU
becoming a full-size one on the CPU reference. **The premise was checked before it was built on and it
held**: MEASURED on the striping zoo at a budget one byte under `peakCompositeTextures · textureBytes`,
`attempt` on the whole lower half answers `.unavailable` with `Admission.overBudget`, and `attempt` on
every band of that same half answers `.image`. `SandwichRecipe.compositeHalves` is the fix — each half
is an ordinary `FrameRecipe` through `StripedCompositor`, one budget account, no second arithmetic —
and `resolve()` stays as the *definition* of the cut with nothing on the canvas resolving it.
**Striping costs a fitting document nothing**, and that is a property of the code rather than a
measurement to be trusted: `plan` answers one strip, `ChunkedCompositor` answers one chunk, and
`testAFittingDocumentStillCostsExactlyOneCompositePerHalf` pins the probe at exactly two composites at
the frame's own size. `LiveHalvesStripLogicTests` (8) and `LiveHalvesStripMetalLogicTests` (4) are the
pin; **only one of the twelve reds when the routing is removed**, and it is the probe one — the
byte-for-byte tests stay green under that mutation, because the defect was never a wrong picture.

**`StripedCompositor.assemble` bounded the walk and not the destination**, and that is fixed in the same
change. It collected every strip's crop and then drew them into one full-frame renderer — a peak of about
two frames, ~1 GB at 16383², and worse than it reads because `CGImage.cropping` retains the image it
cropped, so the array held each strip's whole *buffer* rather than its core. Each strip is now composited
and drawn inside the renderer's own closure under an `autoreleasepool`, taking the peak to the frame plus
**one** strip. What is left is the destination itself, which is a whole frame by construction and belongs
to the separate "16383² cannot be composited at all" item.

**A frame that fits takes the unstripped path verbatim** — `plan` answers one strip covering everything, and
`composite` hands the unwindowed recipe straight to `ChunkedCompositor` with no window, no apron, no crop and no
reassembly. That is a property of the code rather than of the output, and `testAFrameThatFitsIsCompositedWithNoWindowAtAll`
asserts it through the window rather than through the pixels.

`CompositorSizeGate` and the Resize sheet's warning built on it are **deleted** (§2.15). Both halves of what it said
were consequences of `affordableSize`: the canvas no longer softens at any size, and the eyedropper's native
composite is stripped rather than dropped to the CPU reference. A picker that "tells the truth" has nothing left to
tell.

### 3.9 Export

Video: walk the store in frame order, hand each decoded BGRA frame to `AVAssetWriter` as a `CVPixelBuffer`, H.264 in
`.mp4` at the document's fps and the knob's resolution, no alpha. Frame: the baked frame as PNG (alpha survives when
the paper is hidden). Both wait for missing bakes with visible progress and neither composites anything. Delivery is
the system share sheet. One store serves both (§2.9); nothing so far forces a second renderer.

**Built 2026-09-02 (stage 6). `Engine/FrameExport.swift` is the pure half, `Engine/FrameExportSession.swift` the
driver, `Views/ExportSheet.swift` the sheet. Nothing forced a second renderer** — the export file imports no
compositor at all, and its only pixel source is `FrameBakeStore.loadDecoded`. Five things the paragraph above does
not say.

- **An export is a scrub, so the scheduler needed one field and no second queue.** §3.6 orders the bake around the
  playhead and an export walks 1..N; those look like different orders and are the same order seen from a different
  place to stand. `BakeQueue.next` is already a pure function of the playhead it is handed and re-derives all three
  bands every call — its own doc comment says *"an artist scrubbing the timeline therefore reorders the whole queue
  at no cost"* — so `FrameBaker.exportFocus` substitutes a **virtual playhead** and band 1 answers the frame the
  export is blocked on while band 2 prebakes the frames it will ask for next. Two things then follow rather than
  being built: `FrameBakeStore.store(…, playhead:)` reads the same local, so its *"files farthest from the playhead
  go first"* eviction drops what the export has already written instead of what it is about to read; and
  `fillRingAhead` warms the ring ahead of the cursor. The focus also replaces the loop markers in band 2, because an
  artist can export a document whose markers cover four frames of it, and it forces `looping: false` — band 2 wrapping
  would send the export back behind itself.
- **The frame count is `playbackStartFrame...playbackEndFrame`, and the other two answers are both wrong in a way
  that ships.** `sceneFrameCount` is the *laid-out* track — 12 on a new document — so an export driven by it ships
  empty frames, which is the exact bug `contentEndFrame` was introduced to fix for playback. `contentEndFrame` is
  right about content and blind to intent, and it is already what `playbackEndFrame` falls back to with no markers
  set. So the artist exports what pressing play would show, and there is one account of "how long is this" rather
  than a second one inside export. It is then clamped into `0..<sceneFrameCount`, which is **not** belt and braces:
  `BakeQueue`'s universe is that range and `markDirty` silently drops anything outside it, so an unclamped frame is an
  export that waits for ever rather than one that errors.
- **Premultiplied BGRA reinterpreted as opaque BGRA is already the frame composited over black**, so the video
  conversion touches no colour channel at all. Source-over onto an opaque backdrop is `src.rgb + (1 - src.a) ·
  backdrop`, and at black the second term vanishes exactly — no division, no rounding, one byte per pixel. With the
  paper visible (the default) every pixel is opaque and the choice is unobservable; it is reachable only with the
  paper hidden, which is asking for transparency in a container that has none.
- **PNG is the opposite and is the one that goes wrong quietly.** It wants *straight* alpha, so the un-premultiply
  (`c · 255 / a`, rounded, clamped) happens here rather than being left to ImageIO — which does do it, but silently,
  and the failure mode when it stops is a dark fringe on every soft edge and no error. MEASURED by deleting the
  three `straighten` calls: `testPNGStoresStraightColourRatherThanPremultiplied` reads **127.5 back out of the file
  where 255 belongs**, which is that fringe as a number. `CGImage` accepts `CGImageAlphaInfo.last` from a data
  provider (a `CGBitmapContext` would not), which is why that route is a provider and never a context.
- **`AVAssetWriter` takes an odd frame size**, MEASURED: 63x33 in, 63x33 back out of `AVAssetReader`. That matters
  because three quarters of an odd canvas is odd, and a movie one pixel wider than the artwork would be a wrong file
  with no error.

**The driver is tested, and writing the tests found two shipped defects.** `FrameExportSessionLogicTests` is 13
green over it: §2.1 counted with `CompositeProbe` — zero composites on a warm export, with four frames read back
out of the movie so the zero is a walk that delivered — the frame walk asserted off the greys the movie decodes
back rather than off a range the session also computes, the focus hand-back on all three exits, the phase
sequence, and every `Failure` but two. One XCUITest in `ToolPanelsUITests` covers the artist's path: row, sheet,
running view, `ShareLink`, `ActivityListView`.

**`manager` was `unowned`, and an export unwinding after the document closed aborted the process.** `cancel()`
only *asks* — `withCheckedContinuation` is not interrupted by cancellation, so a walk suspended inside `offMain`
finishes what it is doing and only then unwinds through `run` into `endFocus()`, which dereferences the manager;
`ContentView` **replaces** its `@State` `CanvasManager` on `openProject`/`startNewProject`, two taps from the
sheet the artist just dismissed, against a `VideoFrameWriter.finish()` that is seconds long on a real document.
It is `weak` now, and a vanished document ends the walk the way a cancel does, through one `liveDocument()` that
throws `CancellationError` and is read afresh at each use. **Strong was rejected**: it would keep a closed
document's cels, its store bookkeeping and a 96 MiB decoded ring resident on the device this feature exists to
fit inside, and would invert the ownership `FrameBaker.manager` already establishes.

**And the progress bar ran backwards once per frame.** `fraction` gave `baking` the first half of the bar and
`writing` the second, but the video loop bakes *and* writes each frame before touching the next, so the phase
alternates all the way down: MEASURED `0, 0, .17, .5, .17, .33, .67, .33, .5, .83, 1.0` for three frames. `done`
counts frames complete in both phases now and a frame is two steps of `1/2N`.

**Still owed**: `unreadableFrame` (which may be unreachable — `FrameBakeStore.loadDecoded` rejects every
malformed file as a *miss* by design, so proving it either way is a reading exercise rather than a fixture), the
PNG write refusal, `bakeFailed(.exceedsCeiling)` (no seam — `manager.frameBaker` is a `private(set) lazy var` and
the store's ceiling has no override), the five `VideoFrameWriter.Failure` sentences, §3.9's two "free"
consequences of the focus — that eviction drops what the export has written and that `fillRingAhead` warms ahead
of the cursor — and **nothing has run on the device**.

**`FrameBaker.exportFocus`'s doc claim of "free readahead" from band 2 is conditional, not automatic.**
`requestExport` marks only the frame it is blocked on, so band 2 can prebake only frames that are *already*
dirty. In the app the first sweep marks everything and it holds; driven from a cold store with no sweep, the
export walks strictly one frame at a time.

**§2.8's stale copy is fixed here rather than left.** `ActionsMenu.renderResolutionControl`'s subtitle promised
*"Your artwork, exports and thumbnails are always saved at full size"*, and stage 4d made the middle third of that
false by putting the knob inside the bake — export reads those files, so the knob **is** the export resolution. It
now says playback and exports come out at this size and the document's own layers do not, and the export sheet
repeats the pixel size at the moment the artist is about to hand a file to somebody. Thumbnails are unaffected and
the claim is dropped rather than restated: the gallery thumbnail is `sizing: .fitting` and the eyedropper `.native`,
so neither reads the knob. `RenderResolution`'s own doc comment still says *"It reaches only `makeSandwichRecipe`"*
and *"cannot degrade anything that is written to disk or looked at later"* — **both stale since stage 4d**, and not
corrected by this change.

### 3.9a The keep-the-bake option is deferred, and the stamp is decided

§2.11 gives the artist an option to keep the bake beside the project, and §3.5 says stage 6 picks between **a per-cel
content stamp saved in the manifest** and **a hash of the cel's encoded tiers**. Stage 6 picked the hash and did not
build it, and the reason for the split is that the option is not one field — it is a fourth store with a lifecycle.

**The manifest stamp is rejected, on evidence this file already carries.** It has to be bumped on every edit, and
§3.6 established at length that **there is no push funnel in this model that knows a content change**: `recordUndo`
has seventeen call sites and the undo *closures* do not go through it, `objectWillChange` misses the mutation that
matters most because a dab lands in a class, and `beginCanvasEdit` runs before an edit rather than after. That is
precisely why dirty marking is a **sweep**. A stamp bumped from edit sites inherits every one of those holes, and a
missed site in a *persistent* content-addressed store is the wrong picture served with no error — the failure §3.5
says the store has no second chance about. Bumping it from the sweep instead does not rescue it: the counter is
monotonic, so undo and redo both move it forward and every reopened document re-bakes everything it ever edited.

**The encoded-tier hash has none of that** — it is exact, needs no hook, survives undo, redo and reopen identically
because the same bytes hash the same, and `ProjectStore` already encodes exactly those tiers on save. Its cost is
that hashing a cel's pixels per frame per mint would put canvas-area work back on the main actor, which §3.1 exists
to remove; so it **must be memoized against the in-memory version counters the process-lifetime key already reads**
(`RasterLayerTexture.version`, `VectorCanvas.version`), making it one hash per cel per edit rather than one per
frame. The first mint after opening a document still hashes every cel once, and that is the real cost to measure
before building it.

**And the stamp is not the whole of it, which is the argument for a stage rather than a corner of this one.** Three
more things are unanswered: `AlphaMask.tuningGeneration` is in the key (§3.3) and is an in-memory counter that
restarts at 0 every launch, so two different tunings both read as generation 0 across a relaunch and collide — it
has to become a hash of the tuning *values*; a kept store lives at `Documents/Projects/<Name>.paintbake/` and needs
a rename, delete and orphan-sweep policy that `Library/Caches` gets from the OS for free; and `FrameBakeStore` has no
format-migration path, so a stored bake outlives the code that wrote it in a way a cache never does. None of that is
export, and none of it should ride in on export's back.
### 3.10 What a composite is not

Floating Move pieces, lasso floats, motion-group overlays, guides and onion skins are drawn outside every cel and are
in no composite (`RenderRequest.swift:741-789`). A baked frame is the artwork, not the screen. `sandwichEngagesOnCanvas`
(`RenderRequest.swift:815-819`) is the live-canvas predicate and is not the bake predicate: a document with one plain
vector layer still bakes, because play and export need it.

## 4. Shared engine state the baker inherits

- `CompositorMetalEngine` holds one `NSLock` across a whole composite. Its scratch pool and `EffectPipelines`'
  intermediates are bounded LRU maps over `TexturePixelSize` — `residentPoolSizeLimit` sizes each, one high-water
  mark per pool, the map's total inside `CompositorBudget.textureBudgetBytes` — so a consumer at a new size evicts
  the least recently used pool rather than whichever one the live canvas is holding. **The baker is the third
  consumer that limit is sized for**; a fourth means raising it, not changing the rule.
- `Compositor.backend`, `CompositorBudget.budgetOverrideBytes` and `AlphaMask`'s two tunables plus `tuningGeneration`
  are accessors over a lock, and the tuning is one `AlphaMask.Tuning` snapshot so `coverage(forSourceAlpha:)` cannot
  read a pair from two different writes. The bake key (§3.3) reads them through those accessors. Nothing on a render
  queue touches a plain static.
- `UndoHistory` has no lock (`Models/UndoHistory.swift:107`); the baker never records undo.
- `textureBudgetBytes` being static is correct and stays (`Compositor.swift:120-126`): the request and the engine
  must agree on one number, and the baker reads the same one.

## 5. Build order

Each stage merges alone, with a test that would fail without it. Stage 0 first because it is a crash; the order after
it is the dependency order.

0. ~~**Stop the bleeding.** The 16k crash is the live-stroke scratch.~~ **Done 2026-09-02** —
   `Engine/StrokeScratch.swift` is that scratch as a window over the stroke's own dirty rect, and both tiers stamp into
   it rather than into the layer, so nothing on the stroke path scales with canvas area.
   **That last clause was true of the code and false of the gesture, and the device said so.** The artist works at
   `fitScale`, so one screen inch of pen travel is `132 / fitScale` canvas points and grows in direct proportion to the
   canvas — and the window's pad outset *both* axes by half the *longer* one, which squared the box up. MEASURED on the
   owner's iPad 9 in Release: one screen inch at fit zoom held 4.4 MB at 2048² and **283.1 MB at 16383²**, for a stroke
   whose own box is 0.054 MB. Each axis now pads itself, which takes that gesture to 4.42 MB — PERFORMANCE §9 item 1
   carries the numbers and the correction to them. **The clause holds again for the window's own bytes and still does
   not hold for the dab count**, which is `132 / fitScale` dabs an inch whatever the window costs (§9 item 3, and the
   owner has deferred it).
1. ~~**Hoist the playback clock** onto `CanvasManager` (§3.7).~~ **Done 2026-09-01.**
2. ~~**The recipe** (§3.2)~~ **Done 2026-09-02.** `Engine/FrameRecipe.swift` is `FrameRecipe`,
   `SandwichRecipe` and `LeafSnapshot`; `renderSources` is cut at the seam it already had, into
   `CanvasManager.leafSnapshots` (main actor, O(layers), no pixel) and `FrameRecipe.resolveSources`
   (pure, any queue). `makeSandwichRequests` is deleted — `CanvasView.startSandwichRebuild` mints on
   main and resolves inside the `sandwichQueue.async` it already had — and `makeRenderRequest` is
   `makeFrameRecipe(…)?.resolve()` for the callers that are legitimately synchronous. The freeze is
   `PixelOps.FrozenCel`, which is also now the only thing `rasterizeUncached` draws from, so the live
   path and the bake cannot draw a cel differently. `StrokeCanvasView.refreshDisplay` rasterizes the
   committed render on its own queue and holds the finished stroke's scratch until it lands (§2.13);
   `DeferredVectorRender` is the ordering, headless.

   **Two things worth carrying forward.** (a) `VectorCanvas.Frozen` keeps a live reference beside its
   frozen values and renders through `render(quality:ifStillAtVersion:)`, so the composite shares the
   display's memo instead of re-stamping the cel — MEASURED on the owner's iPad 9 in Release,
   2026-09-02: a 20-stroke cel at 2048² is **70.3 ms** to rasterize and **0.0 ms** to read back, so a
   snapshot that carried only the elements would have doubled the very work this stage removes.
   (b) `liveMaskRequest` — §3.1's fourth row — is **not** deferred: both callers need the coverage in
   the turn they ask for it (a `CALayer.mask` at first touch, and the onion skin's cache key). Its
   flattens are memo hits behind the rebuild; the cold case is stage 3's `renderSources(subset:)`,
   not a queue hop.

   The main-thread figure this removes, MEASURED on the same device run: **`snapshotCold` 36.3 ms
   against a 41.6 ms frame budget** — 87% of a frame — plus the 70.3 ms re-render above.
3. ~~**Chunked compositing** (§3.4) with `renderSources(subset:)`.~~ **Done 2026-09-02.**
   `Engine/ChunkedComposite.swift` is the driver — a pure `plan` over the tree, then one ordinary
   `RenderRequest` per chunk — and `FrameRecipe.composite(budgetBytes:)` is how a whole frame becomes an
   image. §3.4 above carries the three places its own text was wrong. `ChunkedCompositeLogicTests` is the
   pin: byte-for-byte on the fixture §5 asked for, at every chunk width from 1 to past the document, with
   and without paper; four fixtures MEASURED red by deleting each rule in turn; and a plan that
   composites nothing. **The two whole-frame consumers are routed through it** — the project thumbnail
   and the eyedropper, whose flatten therefore leaves the main actor as well — so there is no second
   whole-frame path (§2.15). `makeRenderRequest`/`resolve()` stay: `SandwichRecipe` and `liveMaskRequest`
   legitimately want one request over every leaf, and stage 4 is what moves the live canvas.
4. **Store and scheduler** (§3.5, §3.6): the key, the LZ4 files, the ring, the queue, the live canvas and play served
   from it, the timeline's baked-frame indication. MEASURE the compression ratio and the decode time on the device.
   **4a is done, 2026-09-02** — `Engine/FrameBakeKey.swift` and `Engine/FrameBakeStore.swift`, both pure and
   headless; §3.5 above carries the three places its own text was wrong and the two measured ratios.
   `Engine/BakeQueue.swift` and `Engine/DecodedFrameRing.swift` landed the same day from the other half of the
   stage. **4c is done, 2026-09-02** — `Engine/FrameBaker.swift` is the serial loop that joins all five, plus
   the read path (`loadDecoded` → ring → `makeImage`) and the digest→frames map nothing else could own; §3.6
   above carries the dirty-marking finding and §3.5 the deletion. **4d is done** — see below.

   MEASURED on a dedicated iOS 26.5 simulator: `FrameBakerLogicTests`, **21 tests, 0 failed, 0 skipped**,
   static `func test` count reconciled at 21; fast tier **2468 / 2465 passed / 0 failed / 3 skipped** against
   2447 / 2444 / 0 / 3 at `4e91777`, a delta of exactly the 21. **§2.16's acceptance test:** a ten-frame
   document, one cel spanning `[2, 7)`, ten composites the first pass, one edit inside that cel, then
   **exactly five** — dirty set asserted `[2,3,4,5,6]`, those five keys asserted moved and the other five
   asserted unmoved. Three mutations MEASURED red: disabling the `store.contains(key)` dedupe takes the
   nine-frame hold from 1 composite to 9 and the scrub from 0 to 81; deleting `StructuralStamp.effectTracks`
   reds exactly the test whose premise asserts the probe frame's tree is unchanged; dropping the old-span
   `markDirty` for a moved cel reports `[6, 7]` where `[1, 2, 6, 7]` belongs.

   **Two fixture traps worth carrying to 4d.** A document made of holds *cannot* count frames — nine frames of
   one cel are one key and one composite by design — so a test that wants to say "these five frames
   re-rendered" has to give every frame its own picture first. And `CompositeProbe` counts calls to
   `Compositor.composite`, which is once per *chunk*: every count in that suite rests on a 64² canvas planning
   as one chunk, which is why `testABakeOfOneFrameIsExactlyOneComposite` exists as its own test rather than as
   an assumption inside five others.

   **4d is done, 2026-09-02 — the wiring.** `CanvasManager` owns the baker (`syncFrameBake`), the app purges
   the whole bake root at launch (§2.11), and `CanvasView.updateSandwich` reads the rest picture out of it
   instead of compositing it. `startSandwichRebuild` produces **two** halves now; `SandwichFullKey` and the
   layer-tap reuse rule it existed for are deleted, because a key with no field for the active leaf makes a
   layer tap a ring hit rather than a composite worth skipping. Fast tier **2474 / 2471 passed / 0 failed /
   3 skipped** against 2468 / 2465 / 0 / 3 at `84d2dff`, a delta of +7 new and −1 deleted.

   Four things came out differently from what this section and §3.6 said.

   - **The bake mints at `.liveComposite`, not `.native`, and §3.6's *"served by the same worker and the
     same memo"* is bought by the size rather than by the queue.** `PixelOps.rasterize`'s memo is keyed on
     cel version **and size**, and so is `MaskResolver.CacheKey`. A bake at `.native` beside halves at
     `liveCompositeSize` flattens every cel twice at two sizes into one byte-budgeted memo, and the two
     working sets evict each other — §11's 276 ms flatten doubled, on the knob position the artist chose to
     make things cheaper. So the mid-stroke halves **stay on `sandwichQueue`** and that is a documented
     boundary rather than an omission: they are a different product (cut at the active leaf, wanted *now* on
     the artist's own gesture, never stored) and they want `.userInitiated` where the bake wants `.utility`.
     Sharing the size is what §3.6 actually needed. The knob is now inside the bake, which is also what §2.8
     wants of an export that reads these files and what makes `defaultRoot`'s per-resolution directory
     something other than three copies of one picture.
   - **`isSandwichRebuilding` is not a discard, and §3.6's claim that its behaviour "is not inherited" was
     already satisfied.** `finishSandwichRebuild` ends in `reconcileLayers()`, which re-derives the key from
     the model and starts the rebuild the guard declined — the same "waits one iteration" contract
     `FrameBaker.isBaking` has. Deleting the guard is not available: the halves run on a **serial** queue, so
     one rebuild per SwiftUI pass would hand a two-second scrub a backlog of ~120 jobs, ~20 s of
     `.userInitiated` work for pictures nobody will see. The flag stays; the comment claiming the declined
     request is "simply lost" is what was wrong and is gone.
   - **The loop cannot fill the ring on its own.** A bake job rings the frame it wrote, so the ring is warm
     for whatever the pass that *dirtied* the document reached — and playback dirties nothing. On the second
     lap every frame is clean, `BakeQueue.next` answers nil, and every tick past the surviving handful would
     decode on the display thread, which is exactly what §3.5 rules out. `FrameBaker.fillRingAhead` closes it
     from `keyByFrame`, one frame per iteration under the same `isBaking` exclusion. **It needs an outward-only
     marker or it does not terminate**: the ring is routinely narrower than the lookahead (24 frames at 8.4 MB
     is 200 MB against a 96 MiB budget), so a plain rescan fills a far frame, evicts a near one, finds the near
     one missing, and never converges — while leaving the *far* end of the window resident, which is backwards.
   - **"Rest" is now an eventual state in the UI tests**, and every instant `XCTAssertEqual(sandwichState,
     "rest")` had to become `waitForSandwichState`. MEASURED on the iOS 26.5 simulator at the app's default
     2048² canvas: **0.40 s to rest after a stroke, 0.024 s after a frame step** — §2.13's "split second",
     with the artist's ink on screen throughout because the mid-stroke pair is what is held until it lands.
     The old path composited `full` at `.userInitiated` in the same turn, so no test had ever had to wait.

   **Still owed from stage 4** (at 4d): the timeline's baked-frame indication, and the device measurement of
   the compression ratio and the decode time on the owner's "UI Test" document. **4f closes the first**; see
   below.

   **4e is done, 2026-09-02, on the owner's iPad in Release** — the ratio, the decode and the encode
   measured on artwork at 2048x1024, 2048² and 4096², in `PerfBaselineTests`; §3.5 above carries what it
   changed and PERFORMANCE §10 the tables. The headline: **54-73x on cel art; a frame on screen in 1.5 ms
   at the owner's canvas and 24.6 ms at 4096² against a 41.6 ms budget; 4c's copy elimination measured on
   both sides of it at 1.6-2.8x; and §3.5's per-row-filter fallback refuted rather than deferred.**
   **Still owed: the ratio on the owner's own "UI Test" document** — these fixtures are synthetic,
   deliberately shaped like §2.8's document but not drawn by them — and a decode measured against a frame
   the *compositor* produced at the owner's canvas rather than one drawn for the purpose.

   **4f is done, 2026-09-02 — the timeline's baked-frame indication**, which was the last item on this stage's
   own list. §3.7 above carries the four places its own text was wrong, chiefly that the `isBaked(atFrame:)` it
   named as the read path was a recipe mint per frame and could not have served a ruler at all. Fast tier **2554
   / 2551 passed / 0 failed / 3 skipped** against 2536 / 2533 / 0 / 3 at `4d9c346`, a delta of exactly the 18 new
   (`TimelineBakeBarLogicTests` 14, `FrameBakerLogicTests` 21 → 25). Three mutations MEASURED red: dropping
   `!bakeQueue.isPending(frame)` from `isBaked` reports the five frames of an edited cel as ready to play while
   their files still hold the picture from before the edit; dropping the throttle's `guard !isScheduled` takes
   200 landed frames from 1 refresh to 200; and dropping the trailing `if let open` in `unbakedSpans` silently
   loses every run that reaches the last frame — a band that stops one frame short of the end.

   **Two fixture findings from the UI half, both measured by instrumenting the bar inside the app rather than by
   reading the code.** A blend-mode change is the obvious trigger (§3.6 dirties every frame) and is unusable:
   `setBlendMode` is six XCUITest interactions and **the bake finishes inside them**, so the first query after it
   returns sees a fully baked document. The bar was non-empty for **2.4 s in total** across one such session, in
   bursts of a few hundred milliseconds — real, and every burst closed before a query could land. Undo is one tap
   and the next query is inside the window. And the default document is **one cel spanning all twelve frames**
   (MEASURED `(start: 0, length: 12)`, no second cel), so stepping the playhead forward and drawing again draws
   into the hold: four strokes made one bake key, and a test built that way was measuring a one-composite bake.
   That is §5's own "a document made of holds cannot count frames", reached from the UI side.
5. ~~**Strips** (§3.8), then remove `affordableSize` from the live path and make the picker read as the canvas
   does.~~ **Done 2026-09-02.** `Engine/StripedComposite.swift` is the driver and §3.8 above carries the five places
   its own text was wrong. `affordableSize` is gone from `CompositorBudget` outright, along with
   `CanvasManager.budgetTextures`, `CompositorSizeGate`, `CanvasManager.compositorSizeGate` and the Resize sheet's
   `compositorWarning` — the picker has nothing left to tell, because the canvas no longer composites below the
   knob. MEASURED on a dedicated iOS 26.5 simulator: `StripedCompositeLogicTests` **17 tests**,
   `StripedCompositeMetalLogicTests` **12 tests, 0 skipped**, static `func test` counts reconciled at 17 and 12; fast
   tier **2581 / 2578 passed / 0 failed / 3 skipped**, taken after rebasing onto 4f, against 2554 / 2551 / 0 / 3 at
   `4847123` — a delta of +29 new and −2 deleted, and the two deleted are `CanvasResizeLogicTests`' pair on
   `CompositorSizeGate`.

   **Five mutations MEASURED red**, each restored after: the apron forced to 0 reds six of the CPU suite's
   seventeen (a blur at a seam reading its own clamped edge, 255 against 254, and an Outline at 128 against 0);
   `Effect.passes(inFrameAt:)` returning `passes` unstamped reds five (noise at 29 against 158 — row 16 showing row
   0's grain); `RasterizeKey.window` forced nil reds eight (the top band's bar repeated, 255 against 0);
   `MaskResolver.CacheKey.window` forced nil reds **exactly one**, which is the tell that only its own fixture has a
   mask on a stripped frame; and `UploadCache.Key.window` forced nil reds six of the Metal suite's twelve and **none
   of the CPU suite's seventeen**.

   **Still owed: the owner's confirmation on the device.** The knob-versus-canvas symptom is TODO (31)'s first
   report, taken on the "UI Test" canvas on their iPad 9, and nothing here has been run on that.
6. **Export** (§3.9). **Landed 2026-09-02, partially.** `Engine/FrameExport.swift`,
   `Engine/FrameExportSession.swift`, `Views/ExportSheet.swift` and one field on `FrameBaker`
   (`exportFocus`); §3.9 above carries the five places its own text was thin and §3.9a defers the
   keep-the-bake option with the stamp decided. **`FrameExportLogicTests`, 14 tests, 0 failed,
   0 skipped, static `func test` count reconciled at 14**, MEASURED on a dedicated iOS 26.5
   simulator. One mutation MEASURED red, restored after: deleting the three `straighten` calls from
   `unpremultipliedRGBA` reds two, and the informative one reads **127.5 back out of the PNG where
   255 belongs** — the dark fringe as a number, taken from the file through ImageIO rather than from
   the suite's own arithmetic. **Owed: the driver and the sheet are untested** (the frame walk, the
   focus hand-back, the progress phases), there is no XCUITest, and nothing has run on the device.
7. **The rest of the memory audit** (BUGS.md): fill-session budget, blanked hosts, count-only caches to byte
   budgets, a `MemoryPressure` seam so Android and Windows can signal eviction, undo cost for whole-cel raster steps,
   `SaveSnapshot` off the main actor.

## 6. Superseded

LAYER_COMPOSITING §9.2 and KEYFRAMES §4.6 are replaced by §3.5-3.7 above: the store is one, the policy is
"current frame, then ahead of the playhead", and a span is an ordinary run of frames in the same queue. KEYFRAMES
§2.19, §2.20 and §2.25 stand: smooth playback comes from this cache and not from baking cels, the frames the artist
is about to see are complete and eager, and a derived frame may cost more than 1/24 s because the prebake is what
plays.
