# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first

**Run the full suite.** It is owed and nothing else should start before it. The last one was at
`35c0db6`; since then the compositor gained striped rendering, the live canvas and playback moved onto
an on-disk bake, and `CanvasView`'s sandwich path was substantially rewritten — so the suite is
measuring a genuinely different program and no result from before it transfers.

```bash
pgrep -x xcodebuild                          # nobody else on the machine?
top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1     # idle, or the numbers are void
xcrun simctl shutdown all; xcrun simctl erase 75C8B97E-47AF-484B-B7D2-CA7EB1B51B03
tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination 'platform=iOS Simulator,id=75C8B97E-47AF-484B-B7D2-CA7EB1B51B03' \
  -derivedDataPath build/DerivedData
```

**Pull the per-class table immediately afterwards**, before running anything else against that derived
data path — the triage runs that follow a full suite evict its own bundle, and CLAUDE.md's cost model
is asking to be re-taken. Two XCUITest classes are new since the last table (`BakeWiringUITests`,
`TimelineBakeIndicationUITests`, `DistortUITests`) and one class was deleted from `PerfBaselineTests`.

**Expect some red, and triage it before believing it.** An isolated re-run is thirty seconds and the
answer is usually environmental; CLAUDE.md's triage section is exact about how. Two specific things to
suspect first, both new:

- **"Rest" is an eventual state now** — MEASURED 0.40 s after a stroke, 0.024 s after a frame step.
  Any test asserting the canvas has settled *immediately* is racing. `PaintUITestCase.waitForSandwichState`
  is the helper; `"off"` is deliberately not waited for, because disengaging is synchronous.
- **A background program, not the suite, has been the cause three times running.** Adobe's daemons at
  ~250% across 8 cores with no Adobe app open; then `StocksWidget` at 76.7%, which took the machine
  from 52.7% idle to **0.0%**. Read the real number, kill the offender (standing permission), re-measure.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**Two branches were in flight when this pass ran out of budget.** Each was told to commit before it
died, which this repo does because a background agent does not survive a limit and its committed work
does. **None has been reviewed or merged. Harvest their commits; do not trust their working trees** — a
worker's tree legitimately holds deliberate poison from mutation testing, and this repo shipped that to
`main` once.

- **`tmp/render-export`** — RENDER stage 6, export. Two commits. **The design question the stage turns
  on is answered**: *an export is a scrub*, so the playhead-ordered scheduler needed one field and no
  second queue — an export walking 1..N is the same shape as an artist dragging the playhead, which the
  queue already serves. Build on that rather than re-deriving it. Read its commits before its tree.
- **`tmp/dab-bake`** — KEYFRAMES stage 4, the rest-space dab bake. One checkpoint, *"engine and render
  seam, does not build yet"*. Its acceptance signal already exists: stage 5 left
  `testGrainReSamplesUnderAPoseWhichIsTheArtifactStageFourRemoves` **written to go red when this lands**.

**None of the three had a green test run.** Treat every one as a starting point, not as work to finish
blind — and note that `tmp/live-halves-strips` may have nothing on it at all, in which case the
regression below is unstarted and its premise is still unconfirmed.

### The regression stage 5 introduced is fixed, and its lesson outlives it

Stage 5 deleted `affordableSize` and striped the whole frame, but **the two mid-stroke sandwich halves
were not routed with it**, so a document over the budget fell to CoreGraphics for the length of every
stroke — 203 ms where striping costs 84. Fixed and merged; the halves go through the same striped path,
and `assemble` now holds frame + one strip rather than frame + every strip (`CGImage.cropping` retains
the buffer it cropped, so `pieces` was holding whole strips, not cores).

**The lesson is about the tests, not the fix.** Reverting it reds **exactly one of the twelve** new
tests. Every byte-for-byte test stays green, because the defect was never a wrong picture — it is the
same pixels down a path that costs two and a half times as much. **A suite built on stage 5's own
template — byte-identity at several strip heights, on both backends — would have been completely green
against the regression that stage shipped.** The load-bearing test asserts the budget *inequality*
through `CompositeProbe` and `CompositorMetalEngine.lastAdmission`, not a strip count and not a pixel.
When the property you care about is *which path ran*, no amount of comparing outputs will see it.

Two things that fix found which nothing had named: **`MetalCompositor.attempt`'s guard counts
`peakCompositeTextures`, not sources** — 2 for a flat stack of any length — so a hundred-leaf flat
document is admitted while holding 840 MB of sources the guard never sees; and the halves now resolve
only the leaves each half reads, which is *less* rasterization than the shared whole-document resolve
they had.

## RENDER (29): stages 0 through 5 are merged, and export is what is left

[RENDER.md](RENDER.md) is the specification. **§2 is sixteen owner rulings; read them rather than
re-deriving them.** §5 is the build order.

The app now runs on the bake. `Engine/FrameBakeKey.swift`, `FrameBakeStore.swift`, `BakeQueue.swift`,
`DecodedFrameRing.swift`, `FrameBaker.swift` and `StripedComposite.swift` are the machinery; the live
canvas at rest and playback are served from LZ4 files on disk, and the timeline shows which frames are
not yet ready to play.

**Stage 6 is export (§3.9) and it is next.** Video is `AVAssetWriter` over the store in frame order,
H.264 in `.mp4` at the document's fps and the knob's resolution; a frame is the baked frame as PNG.
**Both re-render nothing** — that is §2.1 and it is the whole reason the store exists. Delivery is the
system share sheet. §3.9 says nothing so far forces a second renderer; if something does, say so and
proceed.

Then **stage 7, the rest of the memory audit** (BUGS.md's ranked sites plus PERFORMANCE §9): the
fill-session budget, blanked hosts, count-only caches moved to byte budgets, a `MemoryPressure` seam so
Android and Windows can signal eviction, undo cost for whole-cel raster steps, and `SaveSnapshot` off
the main actor.

**Small things stage 4 left behind**, each a few minutes:

- `FrameBaker.reset()` and `markEverythingDirty()` have tests and **no app caller** — confirmed, the
  only callers are `FrameBakerLogicTests`. `markEverythingDirty` is redundant by its own doc comment
  (the structural sweep already carries `maskTuningGeneration` and `backend`, its two named inputs), so
  it is a straight delete. **`reset()` is the one to think about rather than delete reflexively**: it
  covers document close and a store purged underneath, and it is dead only because a re-root discards
  the whole baker. Whether that discard is the right lifecycle is the actual question — answer it, then
  wire or delete.
- The compression ratio on the owner's own **"UI Test"** document, and a decode against a frame the
  *compositor* produced rather than one drawn for the purpose. PERFORMANCE §10.4 records both as owed.
- **Nobody has looked at the timeline's amber strip on a screen.** Its tests assert the encoded
  accessibility value, not pixels. Granting simulator access from the panel's "Let Claude use it" link
  makes this a two-minute check.
- Stage 5 is simulator-only. **The owner reported the resolution bug on their iPad, on a canvas called
  "UI Test", and should confirm the fix there.**
- **`StripedCompositor.assemble` bounds the walk but not the destination**: it holds every strip's core
  in `pieces` and then draws them into one full-frame renderer, so the peak is about two frames with no
  budget consulted — roughly a gigabyte at 16383². Whether that is worth fixing on its own or belongs
  with the "16383² cannot be composited at all" item is an open call.
- **Nobody has measured playback end to end since stages 4 and 5 merged.** The decode figures are in
  PERFORMANCE §10; what is unmeasured is whether the baker keeps up with a scrub on the device, and that
  is the measurement that would reopen PERFORMANCE §8's 24 fps ruling.
- **PERFORMANCE §9's "still open from the twelve at `9c9d435`: all of them" wants re-taking.** Chunking
  closed part of audit item 1; the other eleven were not re-audited. The sentence names a commit so it is
  not false as written, but it is no longer a census.

## A review found thirteen candidate defects and reached less than half the code

BUGS.md carries them with line numbers. **One is confirmed** — the bake's dirty sweep does not see a
pose edit, because `Cel.transformTracks` arrived with the keyframe channel and `CelStamp` was written
for the sweep in a different branch, and nobody walked the seam. The general point outlives the fix:
**the sweep is the one place in this design where "what reaches a pixel" and "what the differ compares"
are two hand-maintained lists, and nothing holds them together.**

Twelve more are unverified claims, each checkable in minutes. The two worth checking first are a Distort
bake that may round a non-square crop into a stretch (wrong pixels in a *saved* document, not just on
screen) and a posed derivation that may never reach the Core-Animation path (the feature not working on
one of its two paths — the same shape RENDER stage 3 shipped and had to close later).

**Four subsystems were never reviewed at all**: the bake key and store, striped compositing, the
live-canvas wiring, and the ~230 tests this pass added. That last one is the one to run first, read only
to ask of each test *what would have to break for this to go red* — four fixtures that measured nothing
were found by hand in this pass, and nobody has looked systematically.

## What this pass established, and would otherwise be re-derived

**On the store and the key**

- **A content-addressed disk store cannot be built out of this app's `Hashable` conformances.**
  `LayerContentVersion.hash(into:)` deliberately omits `effect` and is right to — every in-memory cache
  here compares `==` after the bucket lookup, so a collision costs one compare. A store whose filename
  *is* the digest has no second chance. `FrameBakeKey` is a hand-written canonical byte encoder: a
  discriminator per enum case, a length prefix per collection, floats by `bitPattern`, and **no
  `default:` clause anywhere**, so a fourteenth `Effect` case is a compile error rather than a silent
  collision on disk.
- **`COMPRESSION_LZ4` is not portable** and §3.5 chose it *for* portability. Apple's constant wraps the
  stream in `bv41` framing no other LZ4 decoder reads. It is `COMPRESSION_LZ4_RAW`.
- **The per-row Up filter §3.5 held in reserve loses.** MEASURED: it makes every fixture *bigger* (cel
  art +39%, hold +28%) and costs 4.3–8.9 ms each way against a 1.5 ms decode.
- **Decode tracks pixels, not file size.** A hold is a quarter of cel art's file and decodes *slower* at
  every size, so a ring budget must mean *decoded* bytes.
- **Measured on the owner's iPad 9 in Release**: cel art 54.4x–73.2x, holds 135x–151x, painted 1.49x,
  noise 1.00x (the raw-store branch). Decode 1.5–3.1 ms at the owner's canvas against a 41.6 ms frame;
  4096² worst case 24.6 ms, still inside a frame at 1.70x.
- **The simulator inverts that measurement.** Between Debug/simulator and Release/device the two halves
  of the decode moved in *opposite* directions — LZ4 8.9 → 1.4 ms, `CGImage` build 0.8 → 2.6 ms. Debug
  reads as "the codec is 91% of the decode"; the device reads as the reverse. PERFORMANCE §1's "device
  is ~1.3x the simulator" is a *compositing* rule and does not generalise.

**On the scheduler and the canvas**

- **There is no push funnel in this model that knows a frame.** `beginCanvasEdit()` runs *before* an
  edit; `recordUndo`'s stored closures bypass it on replay; and a dab lands in `VectorCanvas` /
  `RasterLayerTexture`, which are classes, so `@Published var layers` is never written. Dirty marking is
  a **sweep** — `syncDirty()` diffs the cel layout against the layout last seen, once per
  `reconcileLayers` pass. That cadence is an identity rather than an estimate: the passes that publish
  are exactly the ones that used to move `SandwichKey`.
- **§3.6's claim that `isSandwichRebuilding` is a drop-if-busy was wrong.** `finishSandwichRebuild` ends
  in `reconcileLayers()`, which re-derives the key and starts the rebuild the guard declined — it always
  was coalesce-and-retry. Deleting it hands a two-second scrub ~120 serial jobs.
- **§3.6's "same worker and same memo" is bought by the buffer size, not the queue.** `PixelOps.rasterize`
  and `MaskResolver.CacheKey` are keyed on width and height, so the bake mints at `.liveComposite`.
- **A ring top-up needs an outward-only marker or it does not terminate.** The ring is routinely narrower
  than the lookahead, so a plain rescan fills a far frame, evicts a near one, finds the near one missing,
  and never converges — while leaving the far end resident, which is backwards.
- **`isBaked(atFrame:)` could not serve the consumer §3.7 names it for.** It was a full recipe mint plus
  a `stat` — correct for one frame, and 300 × layers of it per redraw for a ruler. It is two dictionary
  lookups now, and **both halves are load-bearing**: an edit leaves `keyByFrame` in place, so the recorded
  key names a real file holding the picture from *before* the edit.

**On strips**

- **Strips nest outside chunks, and the nesting is forced rather than chosen.** A chunk hands its
  accumulator to the next chunk *in the same buffer*, so a chunk cannot span two strips. A strip is a
  whole self-contained composite of the entire tree over fewer rows. One budget account:
  `affordableRows` is `chunkSources` solved for height, and a strip that still does not fit is chunked
  with no special case.
- **§3.4's rule 3 does not generalise to strips.** It is dangerous for a *chunk* because a chunk discards
  sources; a strip discards none — it windows every one — so the `.ink` re-walk inside a strip is the
  window of the whole frame's, and the apron covers the kernel's reach past the band.
- **Two effects read absolute position and no apron can pay for them**: `noiseValue` hashes `gid`,
  `screenValue` indexes a Bayer cell by `gid.y & 3`. Both take a frame origin now.
- **Three memos are keyed on buffer size and collide across equal-height strips**, repeating one band
  down the canvas on an ordinary drawing with no effect, mask or blend. `MetalCompositor.UploadCache.Key`
  **has no CoreGraphics counterpart**, so the CPU suite was green on every fixture in the file while the
  GPU repeated a band.

**On poses**

- **KEYFRAMES §8's prescription that a pose identity "must include the frame" is wrong.** What an
  identity owes is what `render` *reads*, and this render reads the resolved per-channel affines — the
  frame is what it reads them *through*. Carrying the maps is sufficient and **strictly tighter**: a
  frame field would mint a second cache entry for every frame of a `step: 2` hold and of the
  constant-hold tail, which is the cost §8's own parenthesis warns about, by the other door.
- **A pose channel needs no "stored base" field.** A value channel needs one because `Layer.effect` holds
  what a slider writes when nothing is keyed; a pose channel's base *is* the cel's geometry.
- **Grain boils under a pose** — `BrushGrain.noiseValue` is read in absolute canvas coordinates at the
  *posed* stamp point, so the texture crawls across the ink instead of travelling with it. §4.2's
  prediction, confirmed. Fixed by KEYFRAMES stage 4's rest-space dab bake, not before; the test is
  written to go **red when stage 4 lands**.

**On Distort**

- **Preview and bake are exact, not bounded** — one accessor feeds both, and `CATransform3D`'s `m14`/`m24`
  perform the same projective divide the bake does. MEASURED 0.0 disagreement over the box interior
  across ±3 rad and both mirrors. Strictly better than §5.17's Freeform latch, and there is no latch.
- **A projective `CATransform3D` draws correctly and hit-tests unreliably.** On an outline view it left a
  distorted piece reshapeable and then undraggable, with the corner grips still working. Only a UI test
  could have said so.
- **Distort reaches the raster floating piece only.** Placed images and text are lassoable solely through
  the vector float, whose map is a `CGAffineTransform`. Text already has a real Distort by its own door
  (Text panel → Corners). A **placed image** is the one kind with no door: six numbers plus a mirror bit
  where a homography needs eight.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. The cap is **3 opus or 6 sonnet at once**
   (1 opus = 2 sonnet).
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned.
3. **A replaced path is deleted, not left beside the new one.** RENDER §2.15 in the owner's words:
   *"very clean and non-redundant, with no peculiarities, and no legacy code left by the previous
   functionality."*
4. **At most one investigation agent at a time.** Building is separate.
5. **Weighty programs may be killed to free the machine.** Standing permission.

## Traps this pass paid for

- **A brief's prescription is a hypothesis.** Fourteen were refuted this pass by the workers holding the
  code, and **five of those were errors in a specification** rather than in a brief. Invite the
  refutation explicitly; it is the cheapest review in the project.
- **A green assertion is only as good as its two operands**, and CLAUDE.md now has a section on it.
  Four fixtures measured nothing in one day: a per-field table that built a fresh `CanvasManager` per row
  and so compared `ObjectIdentifier` allocation addresses (it passed with the field under test **deleted
  from the encoder**); forty rows setting `layers[0].effect` on a raster layer when the render path reads
  `layerEffect(atFrame:)`, which is `kind == .value ? effect : nil`; a §2.16 fixture eaten by the very
  dedupe it was counting, because a cel spanning frames 2–6 *is* a hold and those five frames are one
  key; and a UI probe that matched the black letterbox because it tested *not-white* instead of *dark*.
- **Which pbxproj group a file goes in decides how its `path` resolves.** A test file placed in
  `App sources shared with PaintSoftwareUITests` — whose entries carry a full path from the project root
  — makes a bare filename resolve to `/Name.swift`. This surfaced as a missing *file*; the same misfiling
  one level down surfaces as a missing *symbol*.
- **The near-miss CLAUDE.md describes actually happened.** Two branches appended a test entry after the
  same anchor in `project.pbxproj`. Nothing had to be renumbered **only because both derived their ids
  from the file name** rather than counting off a neighbour.
- **`canvas.host` is itself an accessibility element**, so no descendant of the canvas can be addressed
  by identifier. Adding handle identifiers produces a dead affordance, not a testable one.
- **`xcodebuild` waits on "Unlock Kevin's iPad to Continue" rather than failing** — one run sat twelve
  minutes and then completed by itself. PERFORMANCE §9 had given up at that same wall.
- **Reading an xcresult chosen by `ls -dt` is not reliably reading the run you mean.** It cost one wrong
  "six tests are missing" diagnosis. Reconcile executed against a static `func test` count instead.

## Everything else open

**The owner's asks** are in TODO. (21) keyframes stage 5 and (12) LASSO_MOVE stage 5 both merged this
pass; what remains of each is written in their entries. KEYFRAMES §8's **5b is *animated* Distort** — a
quad keyed across frames — and is a different feature from the Move-box Distort that shipped; §2.13 makes
a pose a quad so the two meet with no migration.

**(31) is now one symptom, not three.** The resolution bug is fixed by strips and the `minificationFilter`
half is fixed; what remains is that **16383² cannot be composited at all** and needs a downscaled display
proxy.

(32)-(34) are small. (22), (24), (35)-(37) and (26)-(30) are unstarted, and the last group needs a design
conversation each.

**Deferred by the owner, not refused:** scaling the stroke sample gate by zoom, which would fix the 8x dab
explosion when zoomed out. It is a permanent quality trade, so it wants an A/B the owner can look at, not
a number.
