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
- `CompositorBudget.affordableSize` shrinks any composite whose textures do not fit `physicalMemory / 16`
  (192 MiB on a 3 GB iPad), whatever the knob says. §2.12 forbids that.
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

### 3.1 What the main thread does today, and what it will do

The compositor is not the freeze. At pen-up the main thread runs, in order (`Views/Canvas/StrokeCanvasView.swift:919-996`,
`Views/CanvasView.swift:363-392`):

| step | where | scales with |
|---|---|---|
| re-rasterise the whole cel — every dab of every stroke — into a fresh canvas-sized bitmap | `StrokeCanvasView.swift:986` → `Engine/VectorLayer.swift:3016` | canvas area × dabs on the cel |
| the snapshot: `renderSources` flattens **every visible leaf** to a canvas-sized `CGImage`, fanned over cores but blocking the caller | `Engine/RenderRequest.swift:883-995`, `Services/PixelOps.swift:45-59` | canvas area × layer count |
| Core Animation converts three `premultipliedLast` RGBA composites to its native BGRA inside the commit | `CanvasView.swift:1531-1535`; BUGS.md "a hitch per stroke-lift" | canvas area × 3 |
| the live mask resolve, `RenderSizing.liveComposite` | `CanvasView.swift`, `liveMaskStrokeBegan` | render size × layers, masked documents |
| 400 ms later: the thumbnail flattens the cel into `celThumbnailRasterBound`, downsamples to 120 px, then publishes a second whole SwiftUI pass | `Models/CanvasManager.swift`, `celThumbnailImage` | bounded, then one SwiftUI pass |

**Those last two used to thrash the flatten memo and no longer do**, which is worth stating because it is the one
figure in this section that moved rather than merely being described. `RasterizeKey` carries width and height
(`PixelOps.swift:156-157`), so the sandwich at its clamped size and a *native* thumbnail minted separate canvas-sized
entries per cel in one 192 MiB memo — six layers at 4096² needing 201 MiB clamped plus 384 MiB native, so the memo
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

One key names the pixels of a frame. It is `SandwichFullKey` (`RenderRequest.swift:471-504`) **with `frame` removed**
and three inputs added that no cache carries today:

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

**Measured again 2026-09-02 (stage 4e), on artwork rather than on a rect — and three of the sentences
above are wrong.** The full tables are PERFORMANCE §10; what belongs here is what they change. The
fixtures are the document §2.8 names: flat cel art (six colours in large hard-edged polygons with real
vector ink stamped over them), a hold (three strokes on transparency), a painted gradient as the honest
pessimistic bound, and seeded noise as the theatrical one. **Byte counts are exact and build-independent;
the milliseconds are simulator/Debug and are owed a device re-take** (the iPad was locked, §10.4).

- **The ratio is high and *rises* with canvas size.** Cel art is **54.4x at 2048x1024, 66.9x at 2048²,
  73.2x at 4096²**; a hold is **135-155x**. A bigger canvas draws the same picture with more flat pixels
  in it, so the incompressible part — the ink's antialiased edges — is a shrinking share. Ten seconds of
  cel art at the owner's canvas is **37 MB**, so the store's 512 MiB ceiling holds about an hour of it
  before §3.3's content addressing is even counted. **The bound that matters is not the noise row, it is
  the painted one at 1.49x**: a smooth gradient has no exact byte repeat and barely compresses at all.
- **"An 8 MiB frame is single-digit milliseconds" is about right at 8 MiB and does not generalise, and
  the reason is the interesting part: decode is proportional to the frame's *pixels*, not to its file.**
  A hold is a quarter of cel art's file and decodes **slower** (11.5 vs 9.8 ms at 2048x1024), because
  LZ4 reconstructs the same 8 MiB either way and a nearly-empty frame is coded as long small-offset
  matches, every LZ4 decoder's slowest path. The decompress is ~90% of `load` at every size; the file
  read — including a genuine `F_NOCACHE` storage read — is **0.2 ms** for a 154 kB cel-art frame.
  **So the decoded ring's "byte budget rather than a count" has to mean *decoded* bytes**, and the
  frames the store mostly holds are not the cheap ones to play.
- **At 4096² a frame does not come off disk inside a play interval at all: 78.7-90.5 ms against 41.6.**
  At the owner's 2048x1024 it is ~10 ms and comfortable. So above about 2048² the ring is not an
  optimisation, it is the mechanism, and it needs enough lead — or enough threads — to cover a frame
  that costs two frame intervals to produce. §2.12 forbids the escape of quietly baking smaller.
- **The encode, which this section never mentions, is ~19 ms a frame at 2048x1024 and 146 ms at 4096²,
  and half of it is the BGRA convert this section already knows how to delete.** `bgraBytes` is 8.8 of
  19.0 ms and 70.9 of 145.6; the `readBack`-into-`bgra8Unorm` change named in the paragraph above would
  let the baker hand the store bytes already in that layout. **That is a measured ~2x on the whole
  per-frame bake cost**, and it is the cheapest thing on the table.
- **The last sentence of the paragraph above is refuted, not deferred.** A per-row Up filter before LZ4
  makes **every fixture bigger** — cel art +39%, a hold +28%, painted +2.5% — and a Sub filter also
  loses everywhere (+8%, +3%, +1.2%). A filter helps a coder that models smooth variation, and LZ4
  matches exact byte sequences instead: a flat region is already one long match, so differencing it to
  zeros codes to the same size, while every hard edge becomes a band of residuals that differ row by row
  where the source rows were byte-identical. The loss is largest exactly where this document has the most
  edges. If the ratio ever does disappoint, reach for a coder that models prediction error at all — not
  a filter in front of a match-only one.

**The key is `SandwichFullKey` minus `frame`, built from a `FrameRecipe` by a hand-written canonical byte
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
and even under `.liveComposite` two positions can land on one size once `affordableSize` clamps them.

**A kept bake needs a stable stamp.** The process-lifetime key uses object identity and in-memory version counters
(`RasterLayerTexture.version`, `VectorCanvas.version`), which restart at every open. A bake the artist keeps beside
the project must key on something the document persists — a per-cel content stamp saved in the manifest and bumped
on every edit, or a hash of the cel's encoded tiers. Stage 6 decides which; stage 4 does not need it because the
default store dies with the process.

A small **decoded ring** holds the frames just ahead of the playhead, under a byte budget rather than a count. Play
never decodes on the display thread: the scheduler decodes ahead into the ring and the tick reads from it.

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

The baker also produces the three sandwich halves for the current frame (`full` keyed as above; `below` and `above`
additionally by the active leaf), so the live canvas is served by the same worker and the same memo, and the stroke
still sits between two finished pictures. **The single-slot drop-if-busy behaviour of `isSandwichRebuilding`
(`CanvasView.swift:1490`) is not inherited**: the queue reorders, it never discards.

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

What this stage did **not** build, and stage 4 still owes: a tick reads the ring. If the frame is not baked the
previous picture stays (§2.10). The timeline shows which frames are baked, the way KEYFRAMES §4.6 wanted for
spans.

### 3.8 Full means full

`affordableSize` (`Compositor.swift:227-236`) stops sizing the live composite. When the native texture set exceeds
the budget the baker composites in **horizontal strips**, each with an apron equal to the summed kernel radius of the
effects in the tree, and writes the strips into one frame. Sources are cropped to the strip plus apron, so the peak
is a strip's worth of textures, and the budget chooses the strip height instead of the resolution. Until strips
land, the picker must at least tell the truth: `CompositorSizeGate.pressure` (`Models/CanvasManager+Document.swift:328-340`)
already computes the effective size and the Resize sheet already shows it; the picker does not.

### 3.9 Export

Video: walk the store in frame order, hand each decoded BGRA frame to `AVAssetWriter` as a `CVPixelBuffer`, H.264 in
`.mp4` at the document's fps and the knob's resolution, no alpha. Frame: the baked frame as PNG (alpha survives when
the paper is hidden). Both wait for missing bakes with visible progress and neither composites anything. Delivery is
the system share sheet. One store serves both (§2.9); nothing so far forces a second renderer.

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
   above carries the dirty-marking finding and §3.5 the deletion. **Still owed (4d): the wiring** — the live
   canvas and play reading frames out of the baker, the timeline's baked-frame indication, and the device
   measurement of both the ratio and the decode time on the owner's "UI Test" document.

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

   stage. **4e is done, 2026-09-02** — the ratio, the decode and the encode measured on artwork at 2048x1024,
   2048² and 4096², in `PerfBaselineTests`; §3.5 above carries what it changed and PERFORMANCE §10 the tables.
   The headline: **54-73x on cel art, decode ~10 ms at the owner's canvas and 79-90 ms at 4096² against a
   41.6 ms budget, encode half format-conversion, and §3.5's per-row-filter fallback refuted.**
   **Still owed: the wiring** — the queue driving the store, the live canvas and play reading frames out of
   it, and the timeline's baked-frame indication. Also owed, and smaller than it was: **§10.2's timings on the
   device.** They were built, signed and queued against the owner's iPad on 2026-09-02 and never ran, because
   the iPad was locked; the ratio figures do not need it, since they are file sizes.
5. **Strips** (§3.8), then remove `affordableSize` from the live path and make the picker read as the canvas does.
6. **Export** (§3.9).
7. **The rest of the memory audit** (BUGS.md): fill-session budget, blanked hosts, count-only caches to byte
   budgets, a `MemoryPressure` seam so Android and Windows can signal eviction, undo cost for whole-cel raster steps,
   `SaveSnapshot` off the main actor.

## 6. Superseded

LAYER_COMPOSITING §9.2 and KEYFRAMES §4.6 are replaced by §3.5-3.7 above: the store is one, the policy is
"current frame, then ahead of the playhead", and a span is an ordinary run of frames in the same queue. KEYFRAMES
§2.19, §2.20 and §2.25 stand: smooth playback comes from this cache and not from baking cels, the frames the artist
is about to see are complete and eager, and a derived frame may cost more than 1/24 s because the prebake is what
plays.
