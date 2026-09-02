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
[accumulator, chunk nodes…] with `background: nil` for k > 0, so `Compositor.composite` needs no new mode.
The chunk width N is chosen from the budget — `N = (textureBudgetBytes − fixed) / textureBytes(renderSize)` — and
the peak is `2 + N + 1 + depth-pairs + ≤2 effect intermediates + masks at 1 B/px`, independent of layer count.
`renderSources` gains a leaf-subset parameter; that is the only change to the snapshot.

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

**A kept bake needs a stable stamp.** The process-lifetime key uses object identity and in-memory version counters
(`RasterLayerTexture.version`, `VectorCanvas.version`), which restart at every open. A bake the artist keeps beside
the project must key on something the document persists — a per-cel content stamp saved in the manifest and bumped
on every edit, or a hash of the cel's encoded tiers. Stage 6 decides which; stage 4 does not need it because the
default store dies with the process.

A small **decoded ring** holds the frames just ahead of the playhead, under a byte budget rather than a count. Play
never decodes on the display thread: the scheduler decodes ahead into the ring and the tick reads from it.

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
   **That last clause is true of the code and false of the gesture, and the device says so.** The artist works at
   `fitScale`, so one screen inch of pen travel is `132 / fitScale` canvas points and grows in direct proportion to the
   canvas — and the window's pad outsets *both* axes by half the *longer* one, which squares the box up. MEASURED on the
   owner's iPad 9 in Release: one screen inch at fit zoom holds 4.4 MB at 2048² and **283.1 MB at 16383²**, for a stroke
   whose own box is 0.054 MB. BUGS.md's entry of 2026-09-02 carries the table and the one-expression fix; the stage is
   not reopened by it, but the claim above should not be read as settled.
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
3. **Chunked compositing** (§3.4) with `renderSources(subset:)`. Pin: chunked equals unchunked byte-for-byte on a
   fixture holding a graded folder at 60% opacity, a mask whose source is above the masked layer, an Outline effect
   at root, Bloom with ink input, a hue-blend leaf, and an isolated folder over a blend — and a fixture that must
   *fail* if any of the four rules is deleted.
4. **Store and scheduler** (§3.5, §3.6): the key, the LZ4 files, the ring, the queue, the live canvas and play served
   from it, the timeline's baked-frame indication. MEASURE the compression ratio and the decode time on the device.
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
