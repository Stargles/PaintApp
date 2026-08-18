# Performance

The owner's ask, verbatim: *"any performance enhancements that can be made to reduce memory, stop
lagspikes, or increase fps?"* This is the answer — a ranked programme, the work deliberately **not**
worth doing, and the questions still open with the measurement that would close each one. The asks
themselves live in [TODO.md](TODO.md); defects found along the way went to [BUGS.md](BUGS.md).

**Every number here carries its provenance.** MEASURED means a figure someone read off a run, with
the device and the canvas named. INFERRED means arithmetic over measured points, and says so. A
number with no label would be worse than no number, because the next session cannot tell which kind
it inherited — this document exists partly because a whole shelf of correct measurements turned out
to be about a canvas nobody uses.

---

## 1. The recalibration, and what it promotes

Every performance number this project collected before 2026-08-17 was measured at 4096×4096. **The
owner animates at 2048×1024** — one eighth the pixels. Any cost that scales with canvas area is
overstated eightfold against the document that actually exists.

Three headline issues shrink to a fraction of their reputation.

**The "~19 fps ceiling" on vector layers is a 4K artifact.** [BUGS.md](BUGS.md) records 53.8 ms per
live-stroke refresh at 4096² and 16.4 ms at 2048², both MEASURED on the owner's iPad 9 in Release
(`PerfBaselineTests.swift:1834-1893`). Fitting `fixed + k·area` through those two points gives
**~10.2 ms at 2048×1024** — about 98 fps in isolation, not 19 (INFERRED). That is still ~61% of a
60 Hz frame budget, on the most latency-sensitive path in the app, so it is worth fixing. It is not
the app's top bottleneck and it should not be the first thing anyone opens.

**The "~3 s to leave to the gallery" is not the thumbnail composite.** That figure was taken against
the full 4K canvas. At 2048×1024 the thumbnail's over-render extrapolates to tens of milliseconds
(INFERRED). The multi-second wait is the whole-document PNG re-encode that navigation gates on
(`ProjectStore.swift:363-471`, called from `ContentView.swift:47-54`), and that cost scales with
**cel count**, not with area. Fixing only the pre-flagged thumbnail would leave the complaint intact.

**`CompositorBudget` is inert at this size.** Six canvas-sized textures are 48 MiB at 2048×1024
against a 192 MiB device-derived budget (`Compositor.swift:167-170`, `physicalMemory / 16` on a 3 GB
iPad 9), so `affordableSize` never shrinks anything. The 384 MiB crash table at
`Compositor.swift:91-97` is 4096² arithmetic. Do not tune these constants.

### What the correction promotes

The bias ran the other way too. **At the owner's canvas the compositor stops being the memory story,
and the costs that replace it do not shrink at all when the canvas does.** Correcting the framing
makes them relatively *more* important, and every one of them is invisible to an area-scaled
benchmark — which is why none has ever been under the microscope.

| Cost | Why it does not scale with area | Where |
|---|---|---|
| `relayout()` on every SwiftUI pass | O(scene frames) + O(total cels), touches no canvas pixels | `TimelineTrackView.swift:71-78` |
| The ruler redraws every frame label | O(scene length), ignores the dirty rect | `TimelineTrackView.swift:624-642` |
| Save re-encodes every PNG in the document | O(cel count) × per-PNG size | `ProjectStore.swift:363-471` |
| Load decodes and rasterizes every cel, serially, on main | O(cel count), fully serial | `ProjectStore.swift:520-675` |
| `UndoHistory.maxCost` = 300 MiB | A hardcoded literal, neither device- nor canvas-derived | `UndoHistory.swift:24` |
| Compositor fixed per-call overhead | A fixed term, paid three times per sandwich rebuild | `RenderTree.swift:429-431`, paid at `CanvasView.swift:1236-1238` |
| Mode 3 eraser re-stamps the whole vector layer per cut | O(total dabs in the layer) | `VectorLayer.swift:615-634`, `:1160-1214` |

Two independent device tables record that per-composite intercept and they do not quite agree:
`RenderTree.swift:429-431` has CoreGraphics 3.9 ms / Metal 7.3 ms, `Compositor.swift:32-33` has 4.2 /
7.0. Both are MEASURED on the iPad 9 in Release at 2048², from different tests. The spread is the
error bar; nothing below turns on which one you pick.

### The device is ~1.3× the simulator, not ~1.1×

[TODO.md](TODO.md) recorded the iPad 9 as roughly 1.1× the simulator for compositing workloads. **The
onion-skin device re-run of 2026-08-18 measures ~1.28× across six paired configurations** (device
vs. simulator, same test, same 4096² canvas: 1.19, 1.31, 1.31, 1.28, 1.29, 1.30). Treat the device as
**~1.3×** when extrapolating a simulator figure. This correction is not about onion skin — it applies
to every simulator number in this repo that anyone plans to reason from, and it is stated here
because §4 is where a future session will look for it.

---

## 2. What the artist actually feels

Ordered by how bad the shape is and how often it happens, with costs at 2048×1024.

**1. Coming back from another app and finding it frozen — the cause is now settled.** The owner was
asked, on 2026-08-18, whether the app returns exactly where they left it or on the Gallery. There is
no `@SceneStorage` anywhere and `ContentView.screen` is plain `@State` (`ContentView.swift:10-11`),
so a genuine relaunch provably resets to the Gallery. Their answer: *"Exactly where I left off. It
only freezes for a few seconds though, which honestly is to be expected unless something bad is going
on in the backend."*

**Exactly where they left off means the process was never killed.** Jetsam is disconfirmed; the app
is doing its own synchronous main-thread work on the return leg, and the mechanism is one missing
condition. `ContentView.swift:30-34` guards on `newPhase == .inactive || newPhase == .background`
with no direction check. SwiftUI passes through `.inactive` on *both* legs, so one background round
trip fires `saveIfNeeded()` three times — one of them on the way back in, while the artist is looking
at the screen. `saveIfNeeded` has no dirty check of any kind (`ContentView.swift:56-68`; the "if
needed" is the screen guard), so each of the three is a full save: a `SaveSnapshot` built
synchronously on `@MainActor` (`ProjectStore.swift:205`, `:295`) that composites the **whole canvas**
to make a 320×320 tile (`:261-265`), *before* `beginBackgroundTask` is even requested at `:303`, then
a full-document PNG re-encode enqueued behind it. Three of those compete for the A13's cores per
switch.

The owner's second sentence allows that a few seconds may be expected. It is not — three full
document saves per switch, one landing while they watch, each compositing 2 M pixels for a 102 k tile
on the main thread *before* the background-time request that was meant to cover it. That is the
"something bad in the backend" their sentence left room for. Mechanism READ-confirmed; the
multi-second magnitude INFERRED, and corroborated by the owner reporting the symptom.

**2. Tapping a project in the gallery and the app going dead.** `ProjectStore.load` is `@MainActor`
and fully serial (`ProjectStore.swift:520-675`): per cel, a PNG decode, then `RasterLayerTexture`
forces a full canvas-sized `CGContext` allocation and draw (`RasterLayerTexture.swift:196-203` →
`:235-247` → `:218-231`), then line **673** runs `regenerateAllThumbnails()` — a second full walk,
guaranteed cache-cold because every fresh texture is a new object identity at version 0.
`GalleryView.open(_:)` calls it inside a Button action with no `Task`, no loading state, no
`ProgressView` anywhere (`GalleryView.swift:110-113`). The cost is driven by cel count, so it does
not shrink at 2048×1024. Plausibly 1-3 s of hard-frozen UI on a hundred-cel project — INFERRED, and
**completely unmeasured**; it appears in neither [BUGS.md](BUGS.md) nor [TODO.md](TODO.md). It is the
first thing that happens every session.

**3. Leaving to the gallery.** Navigation waits on the full write (`ContentView.swift:47-54`), which
re-encodes every PNG in the document regardless of what changed. Encoding is correctly off-main on
`saveQueue`, so nothing freezes — the artist simply waits. Unmeasured at any resolution.

**4. Scrubbing the timeline, and playback dropping frames.** Two ungated main-thread costs fire on
the same `currentFrame` write. `relayout()` runs unconditionally on every SwiftUI pass with no
equality gate — unlike `SandwichKey` (`CanvasView.swift:1161`) and `InterpolationPreviewKey`
(`:1532`), which check `!=` first — redrawing the ruler and re-diffing every cel row.
`updateOnionSkin()` is the only render path in `CanvasView` without a key gate (`:273`, `:1661-1681`),
allocating a canvas-sized bitmap and blitting per pass even though the previous cel is unchanged
within a cel's span. Scrubbing drives both harder than playback does, since `onScrub` fires
unthrottled on every `.changed` sample (`TimelineTrackView.swift:604-607`). Magnitude unmeasured; a
300-frame scene means 300 CoreText layouts per tick.

**5. Playback stuttering on documents with a mask, blend mode, or grade.** `startSandwichRebuild`
computes `full`, `below` and `above` unconditionally (`CanvasView.swift:1236-1238`), but
`below`/`above` are only shown while `midStroke` is true (`:1048-1056`). Every playback tick, scrub
tick, undo and layer switch computes two composites nobody sees. It runs off-main on `sandwichQueue`,
so it burns cores rather than freezing the UI — but `isSandwichRebuilding` serialises, so a rebuild
slower than the frame interval drops frames. A six-layer sandwich rebuild at 2048² costs **54.8 ms
warm on Metal, 64.7 ms on CoreGraphics** (MEASURED, iPad 9, Release, `Compositor.swift:36`) against a
41.6 ms budget at 24 fps: it already misses. Only fires where `needsCompositorOnCanvas` is true; a
flat stack stays on Core Animation and pays none of it.

**6. Drawing on a vector layer feeling heavier than raster.** ~10.2 ms vs ~2.8 ms per touch-move at
2048×1024 (INFERRED from the two MEASURED points in §1). A tax on the frame, not a cap on it — but it
stacks with items 4 and 5 inside the same frame, and together they plausibly do blow 16.7 ms.

---

## 3. The programme

Three tiers. Tier A is work that is correct on its own terms and cheap enough not to need a
measurement first. Tier B is instruments — the point is to stop guessing. Tier C is real, recorded,
and deliberately not urgent.

### Tier A — do these

**1. Make the `scenePhase` save guard direction-aware.** `onChange(of:)` already hands both values;
compare `oldPhase` so the save fires once, on the leaving leg only. Extract a pure
`shouldSave(from:to:)` predicate.
*Win*: removes two of three saves per app switch, including the only one that lands while the artist
is watching — **the confirmed cause of the freeze the owner has been living with** (§2 item 1).
*Safety*: one guard condition, no gesture code, no drawing path; the worst case is a save that stops
firing on some transition, which `ProjectSaveLogicTests` covers.
*Verified*: headless logic test over the predicate — `(active, inactive)` saves, `(background,
inactive)` and `(inactive, active)` do not.

**2. Give project open a loading state.** A `Task` and a `ProgressView` in `GalleryView.open`
(`GalleryView.swift:110-113`) turns a frozen app into a spinner.
*Win*: removes the "it crashed" reading of §2 item 2 entirely, for almost no risk. It does not make
the load faster — items 8 and 9 do that — and it is listed separately precisely because it should not
wait for them.

**3. Gate `TimelineTrackView.relayout()` behind an equality-checked key, and clip the ruler to its
dirty rect.** Build a key struct from cel identity+version, `pixelsPerFrame`, `sceneFrameCount` and
drag state, following the `SandwichKey`/`InterpolationPreviewKey` idiom this codebase already uses
three times; keep a cheap playhead-only fast path. Separately, make `draw(_ rect:)` consult its rect
instead of looping `0..<frameCount` (`TimelineTrackView.swift:637`).
*Win*: identical at 2048×1024 to what it would be at 4K, which is the point — this is the clearest
member of the area-independent category. Eliminates O(scene frames) CoreText layouts and O(total
cels) of view churn on the overwhelming majority of ticks. Magnitude unmeasured.
*Safety*: pure memoization; the failure mode is a stale timeline row, immediately visible. The ruler
clip is independently safe and can land alone.
*Verified*: the key struct is a pure value type — a headless test pins which mutations move it. A
synthetic 300-frame/6-layer timing of `relayout()` sizes the win without a device.

**4. Cache `full` across a pure `activeLayerIndex` change, and compute `below`/`above` lazily.** Two
fixes to the same waste, different in risk. The first is a second cache key excluding
`activeLayerIndex` — `CanvasView.swift:1158-1160` names this fix in its own comment and records that
it was declined only for the cost of that key, not for correctness. The second moves `below`/`above`
off the unconditional path at `:1236-1238`.
*Win*: the layer-switch fix skips one of three composites on every layer tap; the lazy fix skips two
on every non-stroke rebuild, including every playback and scrub tick. A six-layer document at 2048²
costs 54.8 ms per rebuild on Metal (MEASURED, above); the per-layer slope is 2.4 ms and the
per-composite intercept 7.0 ms (MEASURED, `Compositor.swift:32-33`), so `full` alone is roughly
6 × 2.4 + 7.0 ≈ **21 ms** (INFERRED) — from missing the 24 fps budget to fitting inside it.
*Safety*: the layer-switch key changes only *which cached image serves*, never what is displayed —
low risk, take it first. The lazy fix is riskier and structurally so: the current design deliberately
pre-pays `below`/`above` so touch-down has zero composite work, which is what
`RenderRequest.swift:316-320` means when it says those two are the ones that have to be *fast*. A
naive version trades ink latency for playback smoothness at the moment latency matters most. The safe
shape is to kick them off on `sandwichQueue` at `sandwichStrokeBegan` and accept `full`-only for the
first frame or two.
*Verified*: headless, and it is a **call count** rather than a timing. Count `Compositor.composite`
calls across a layer-switch-only pass and across a playback tick, and assert 1 where there are 3
today. No device needed.

**5. Give `makeRenderRequest` a render-size hint.** `makeSandwichRequests` already carries the
machinery — `renderResolution.renderSize(for:)` then `CompositorBudget.affordableSize`
(`RenderRequest.swift:442-444`); this copies an established in-repo pattern to a second call site,
the thumbnail composite at `ProjectStore.swift:261-265`.
*Win*: 2,097,152 pixels composited for the 102,400 the tile needs — 20× waste, on the main thread,
inside every save, and therefore three times per app switch until item 1 lands. Tens of milliseconds
for a plain document (INFERRED), several hundred once the stack carries an effect: six *faded* levels
cost 1071.7 ms against 41.6 ms flat, **roughly 25×** (`PerfBaselineTests.swift:1229-1234`; MEASURED
at 2048² on the CoreGraphics backend, which that test pins deliberately — no device or Release
provenance is recorded for it, so take the ratio and not the absolutes).
*Safety*: localised to one request builder and two callers; the output is a 320×320 tile, so visual
verification is forgiving.
*Verified*: headless — assert the composited size, and compare downscaled tiles.
*Why not higher*: its headline is 4K-inflated. It earns its place because it is cheap, because it is
main-thread, and because it stops being irrelevant the moment the stack carries an effect — which is
exactly the scene an animator builds at the end of a shot.

**6. Wire `MaskResolver.clearCache()` to the memory-warning notification.** One `addObserver` block
copied verbatim from `PixelOps.swift:150-154`.
*Win*: ≤16 MiB at 2048×1024 (8 entries, 1 byte/px coverage, ~2 MiB each — INFERRED). Small; the
≤128 MiB figure that makes this look important is a 4096² number.
*Why do it anyway*: `MaskResolver.swift:133-135`'s doc comment says the method exists "for a memory
warning", and **every call site in the repo is a test** — verified by grep across the whole tree, and
the app contains exactly two `addObserver` calls, neither of them this one. Its real value is closing
a documented lie, not recovering bytes. This is the identical bug class that `PixelOps.swift:145-149`
records having already been found and fixed once. Now also in [BUGS.md](BUGS.md).
*Safety*: `ResolvedMask` is fully re-derivable; two existing observers establish the pattern.
*Verified*: headless — post the notification, assert a fresh resolve.

**7. Merge `tmp/onion` rather than writing an onion-skin fix.** The branch already carries the
`OnionSkinKey` gate that `main`'s unconditional composite at `CanvasView.swift:1661-1681` lacks, is
green at 1120/1123, and **the device re-run that was blocking it has been done** — see §4.
*Win*: the multi-skin feature, plus the per-tick waste of §2 item 4's onion half.
*Safety*: already tested green; the recorded rebase conflict was two spots in `CanvasView.swift` and
the rebase onto current `main` has since been taken cleanly.
*Note*: this adds a fifth static memory budget on top of the four in item 13; land it with that
reconciliation in view.

### Tier B — measure before building

**8. Add a 2048×1024 case to the vector-vs-raster preview perf test.** One more call to the existing
`costs(at:)` closure inside
`testTheLiveStrokePreviewCostsFourTimesMoreOnAVectorLayerThanARaster`
(`PerfBaselineTests.swift:1834-1893`), which today measures 2048² and 4096² and nothing between.
*Win*: none directly. It replaces the two-point linear fit that §1 and §2 both lean on with a real
number.
*Device-only*: the number itself must come from a Release run on the owner's iPad. A simulator figure
is worthless here, and this repo's own history is explicit that the simulator misreports GPU cost by
more than 10×.

**9. Instrument project open, then move its decode off `@MainActor`.** Staged, and the instrument
comes first. (a) A `PerfBaselineTests` case that saves a realistic multi-cel document then times
`ProjectStore.load` end to end, split into the decode loop and `regenerateAllThumbnails()` — the same
shape as `testCompositeCostAndMemoryAtCanvasResolution`. `CanvasManager.thumbnailRegenerationCount`
already exists for exactly this (`CanvasManager.swift:1145-1149`), so "how many uncached rasterizes
did open cost" is a headless assertion rather than a timing. (b) Move the per-cel decode fan-out off
the main thread. (c) Defer thumbnail regeneration to a background pass with placeholders.
*Win*: (a) none directly — but right now nobody can say whether §2 item 2 is 200 ms or 4 s, and that
is **the largest unmeasured quantity in the app**. (b) and (c) cut the wall clock; the size is
unknown until (a) lands.
*Safety*: (a) is test-only. (b) and (c) are threading and `@MainActor` assumptions confined to
`load`; nothing gesture-adjacent, and a wrong answer fails loudly (missing or wrong thumbnails)
rather than subtly.

**10. Measure the Mode 3 eraser (`cutToIntersection`) live-drag cost. Do not fix it yet.**
`recordVectorSample` calls `resolveIntersectionCut` on **every** sample
(`StrokeCanvasView.swift:782-804`, the call at `:795`); on a cut, `VectorCanvas.cutToIntersection`
calls `invalidate()` (`VectorLayer.swift:632` → `:389-393`), nilling the cached image, so the next
`refreshDisplay` re-stamps every stored stroke in the layer through `BrushStamper`
(`VectorLayer.swift:1160-1214`). The cost is O(total dabs), completely independent of canvas
resolution, and no `PerfBaselineTests` scenario exercises it — the existing eraser test uses
`.erase`, not `.cutToIntersection`.
*Why it is here at all, honestly stated*: this item's original motivation was that it was the leading
hypothesis for why the owner's 17 fps report did not fit the ~98 fps the area model predicts at
2048×1024. **That hypothesis is no longer needed** — the report was taken at 4096² (§6), and the area
model holds. What survives is narrower and still true: an O(total dabs) cost on a per-sample path is
structurally invisible to every area-scaled benchmark in the repo, and nobody has ever looked at it.
*Win*: unknown, and that is the honest answer. Cheap to measure, hard to fix — any fix touches
three-mode eraser machinery.
*Verified*: add a scenario reusing `eraseScenePaintStrokes()` (`PerfBaselineTests.swift:986-1003`).

### Tier C — real, recorded, not urgent

**11. Give the `.overlay` vector scratch its own layer.** The fix [BUGS.md](BUGS.md) sketches:
separate layer, let Core Animation composite, deleting three of the four canvas-sized operations at
`StrokeCanvasView.swift:304-314` (the committed render at `:304`, the fresh
`UIGraphicsImageRenderer` allocation at `:311`, and both blits at `:312-313`).
*Win*: ~10.2 ms → ~2.8 ms per touch-move at 2048×1024, ~7.4 ms of frame budget recovered (INFERRED).
At 4096² it is 53.8 → ~4 ms (MEASURED baseline) and genuinely dramatic.
*Why it is in Tier C and not lower*: the recalibration demoted this on the reasoning that its
headline was 4K-inflated and nobody was feeling it. **Half of that is now wrong.** The owner's 17 fps
report was taken at 4096×4096 (§6) — the exact canvas where this change is worth ~50 ms a dab. So
somebody *was* feeling it, on their stress canvas. It stays out of Tier A because the blast radius
has not changed, not because the win is imaginary.
*Risk*: **highest on the board.** [BUGS.md](BUGS.md) calls this the most gesture-sensitive code in
the app; `vectorScratchRole` has three modes that behave differently (`.replacement` at
`StrokeCanvasView.swift:296-300` and `.none` are already one-op paths and must not regress), and
correctness needs the full vector-eraser UI suite — 22 minutes, historically environmental-flaky (see
[CLAUDE.md](CLAUDE.md) on triaging those).
*Sequencing*: item 8 first, so the before/after is a number rather than a fit.

**12. Purge the compositor and flatten caches on backgrounding, not only on a memory warning.**
`MetalCompositor.swift:378-381`'s own doc comment names the exact scenario — caches "sit at their
high-water mark … against a document nobody is looking at" when the artist switches apps — and then
subscribes to the one event the owner reports never arriving (`:386-390`). Add a
`didEnterBackgroundNotification` observer calling the same `purge()`/`removeAll()` that already
exist. There is no `didEnterBackground` observer anywhere in the app; verified by grep.
*Win*: up to ~384 MiB off the background resident footprint (192 MiB Metal + 192 MiB flatten memo,
both device-derived so both at full size here). INFERRED — the budgets and the missing observer are
READ; real cache occupancy is not measured.
*Why it moved down*: this was sized against the jetsam hypothesis, and **the owner's answer
disconfirmed it** (§2 item 1, §6). Keep it as cheap hygiene whose own doc comment already promises
the behaviour — a smaller background footprint is still the right thing on a 3 GB device — but it is
no longer buying a fix for a bug anyone has.
*Safety*: `purgeLocked()` is documented "correctness-neutral by construction"
(`MetalCompositor.swift:393-394`); the cost is one cold composite on return. MEASURED at 2048² on the
iPad 9: a six-layer sandwich rebuild is 108.1 ms cold against 54.8 ms warm on Metal
(`Compositor.swift:36-37`), so about **53 ms of one-time cost** on the frame after a return.
*Verified*: headless — post the notification, assert the upload cache count and rasterize cache are
empty.

**13. Device-scale `UndoHistory.maxCost`, and reconcile the four static budgets.** Derive it from
`physicalMemory` the way `CompositorBudget` already does (`Compositor.swift:167-170`), and on a
memory warning temporarily lower it and re-run `trim()` rather than clearing — undo is user data, not
a cache. Do it alongside a reconciliation of the four static budgets (flatten memo 192 MiB, Metal
192 MiB, undo 300 MiB, mask ~16 MiB), which sum to **~700 MiB** against the ~1.4 GB pre-jetsam
ceiling this repo's own comment cites (`Compositor.swift:102`), before a single cel bitmap.
*Win*: proportionally larger than the 4K framing implies, since 300 MiB is 300 MiB at any canvas
size.
*Why it moved down*: same reason as item 12 — sized against jetsam, and jetsam is disconfirmed. The
~700 MiB arithmetic is still worth having written down.
*Safety*: pure logic, fully headless; the tradeoff is losing deep undo under pressure, which wants
the owner's opinion on trim depth.
*Note*: freehand strokes are already stored as cropped dirty rects
(`StrokeCanvasView.swift:528-555`), so reaching the cap needs many whole-cel operations. Whether real
sessions get there is unmeasured — see §6.

**14. Bound raster-cel residency.** `RasterLayerTexture.init` allocates a full canvas-sized
`CGContext` and draws the decoded PNG in whenever an image is passed (`:196-203` → `:235-247` →
`:218-231`), and `load` does this for every cel of every layer. There is no eviction of any kind —
unlike the vector tier's `evictDistantVectorRenderCaches`
(`CanvasManager+Interpolation.swift:489-511`, capped at 12 cels).
**The asymmetry is principled**: a vector render is re-derivable from
retained geometry; a raster cel's pixels are the primary data. So the fix is different in kind — hold
compressed `Data` for cels outside a playhead window and rehydrate on demand.
*Win*: 8.0 MiB per drawn cel with no ceiling today — ~960 MiB for 120 cels (INFERRED arithmetic) —
against a bounded ~96 MiB with a 12-cel window.
*Risk*: **high, and this is a project not a patch.** It flips the contract from "always-resident
bitmap is the source of truth" to "possibly evicted, rehydrated on demand", and every call site
assuming synchronous availability — drawing, undo restore, thumbnail regen, compositing, save — must
tolerate rehydration or be proven never to hit an evicted cel.
*Why it moved down*: jetsam again. Without a kill to prevent, this is a large refactor of the most
data-critical path in the app for a memory number nobody has yet observed causing harm.
*Verified*: measure first. Extend the `residentBytes`/`measuringPeakMemory` harness
(`PerfBaselineTests.swift:37-46`, `:51`) across a synthetic N-cel manager and assert residency stays
bounded as N grows past the window. Then, separately, assert a scrub to an evicted cel round-trips
pixel-exact against an `alphaFingerprint` taken before eviction. **Do not build this on inference.**

---

## 4. The onion-skin device re-run (2026-08-18)

The plan this document supersedes said: *"Do not trust the 1302 ms / 190 ms onion-skin figures. They
were genuinely MEASURED on the owner's iPad 9 in Release — for a composite sized to 2508² on a 4096²
canvas. Right numbers, wrong document. Re-run at 2048×1024 rather than reasoning from them in either
direction."* **That advice was followed.** `tmp/onion` was rebased onto current `main` cleanly and
the re-run taken at 2048×1024 on the owner's iPad 9 in Release, with 4096² kept as the stress case.

All figures below are **MEASURED, owner's iPad 9, Release, 2026-08-18**, in milliseconds per
composite:

| Resolution setting | composite size | 2 skins | 10 skins |
|---|---|---|---|
| **Owner's canvas, 2048×1024** ||||
| Full | 2048×1024 | 37.4 | 237.1 |
| Half | 1024×512 | 9.4 | 59.8 |
| Quarter | 768×384 | 5.4 | 33.9 |
| **Stress case, 4096×4096** ||||
| Full | 4096×4096 | 311.3 | 1953.8 |
| Half | 2048×2048 | 79.9 | 486.2 |
| Quarter | 1024×1024 | 19.3 | 120.6 |

Quarter on the owner's canvas is 768×384 rather than 512×256 because the branch floors the fraction
at a `readableFloorEdge` of 768 px, which is the measured readability cliff.

**Three findings, and the third is the one worth keeping.**

*The cold-CPU explanation for the old `skins5 > skins10` inversion is confirmed on device.*
`skins5Cold = 98.8 ms` against `skins5 = 56.2 ms` warm, and the warm series is monotonic — 6.1 / 56.2
/ 118.8 ms for 1 / 5 / 10 skins. It was never cache ordering; it was a cold CPU never ramping for a
5 ms burst.

*The device is ~1.3× the simulator for this workload, not the ~1.1× [TODO.md](TODO.md) records.* The
six paired ratios are in §1, and the correction applies well beyond onion skin.

*Onion composite cost is calculable, not merely measurable.* Divide every figure by (composite
megapixels × skin count) and the whole table collapses to **11.5 ms per megapixel per skin at 10
skins, 9.2 at 2 skins** — consistent to within ~3% across both canvases and all three resolution
options. A future session sizing a different configuration does not need another device run; it needs
that constant, the composite size, and the skin count.

**One thing that constant does not explain, and it should be recorded rather than tidied away**: the
per-skin cost *rises* with skin count — 9.2 at two skins, 11.5 at ten, a 25% spread that is far
larger than the ~3% spread across canvases at either count. A fixed per-composite overhead predicts
the opposite (it would make ten skins the *cheaper* per skin), so whatever is happening is
superlinear in skin count rather than constant per composite. Nobody has measured what. It does not
change any decision here — the constant is good enough to size a configuration once the skin count is
fixed — but do not carry it forward as though the model were fully explained.

**The consequence for the merge.** Full at ten skins costs 237 ms at the owner's own canvas, which is
a visible stall on every scrub tick; that is what the owner's ruling on whether Full needs a UI
warning is about. Half and Quarter are both comfortable there. The recorded cache-thrash worry ("Half
+ 10 skins at 4096² fits only ~3 cached sources") is a 4096²-only problem — at 2048×1024 a Half entry
is ~2 MiB rather than ~16 MiB against the same budget, so ~32 fit rather than ~4 — and it is not a
merge blocker.

---

## 5. What not to do

Naming the work that is not worth doing was an explicit requirement of this investigation, and it is
the half a future session is most likely to discard. It carries the same weight as §3.

**Do not tune `CompositorBudget`, `textureBudgetBytes`, or `affordableSize`.** At 2048×1024 six
canvas-sized textures are 48 MiB against a 192 MiB budget. The admission valve never fires. Every
number that forced it into existence is 4096² arithmetic.

**Do not re-derive a problem from the flatten memo's "1.61 GB at 4096²" comment**
(`PixelOps.swift:120-124`). It is historical and already superseded by the byte bound the same
comment describes. At 2048×1024 the 24-entry cap and the byte budget coincide exactly at 192 MiB — no
cliff, no thrash.

**Do not treat `tmp/onion`'s cache-thrash note as a merge blocker.** See §4.

**Do not generalise the non-native-pixel-format entry into an app-wide BGRA /
`premultipliedFirst` contract change.** [BUGS.md](BUGS.md)'s own proposal is narrow and stays narrow
— `bgra8Unorm` for the two accumulator textures — and the temptation this note exists to head off is
reading it as "`premultipliedLast` is wrong". It is not a Metal-path defect.
`CoreGraphicsCompositor.makeImage` (`Compositor.swift:961-967`), `CompositorMetalEngine.readBack`
(`MetalCompositor.swift:865-881`) and `RasterLayerTexture` (`:194`) all choose it deliberately, and
`RenderRequest.swift:69-75` says why: both backends normalise to one layout so their output can be
compared byte for byte, which is the premise the whole parity suite rests on. Changing every producer
at once means re-establishing that premise for a benefit nobody has confirmed exists. The cost is
UNMEASURED at any resolution and scales with area, so the 4K framing overstates it eightfold. **Run
the Instruments "Color Copied Images" pass first** — minutes on the device. Schedule nothing, not
even the narrow version, until it comes back positive and non-trivial. Acting on an unmeasured
inference is this project's documented failure mode.

**Do not adopt predicted touches as part of a performance pass.** `event.predictedTouches(for:)`
appears nowhere in the app (grepped, zero matches), and it makes nothing faster — it hides latency. On
a fixed-60 Hz iPad 9 with a 1st-gen Pencil that is roughly one frame of apparent lead, unquantified
here. It adds state to the touch path where a mistake shows up as ghost ink or dropped tail segments,
which no headless test would catch. Scope it separately if the owner reports ink feeling laggy
independent of frame rate.

**Do not chase these; all were checked and ruled out.** `activeCelIndex(inLayer:atFrame:)`'s linear
scan (`CanvasManager+Timeline.swift:12-15`), the per-cel 120×120 layer-panel thumbnail,
`resolveLiveMask`'s native resolution (correct — it clips a natively-rendered stroke view), gallery
listing, and startup. `runStartupMaintenance` is already `Task.detached` off-main and uses `clonefile`
COW clones; `validateProject` reads an 8-byte PNG magic, not a decode; backup rotation uses
same-volume renames. None is a multi-second stall at any realistic scale.

**Do not build a dirty-tracking save until item 1 has landed and item 9's instrumentation exists.**
Skipping unchanged PNGs is the right eventual answer to the gallery-exit wait, but it is the
data-loss class of risk: a dirty check that is wrong once silently drops artwork, which is worse than
any stall — and this repo already carries `ProjectBackupManager` and `validateProject` precisely
because that failure mode is unacceptable. Item 1 removes two thirds of the cost for one line and zero
correctness exposure. A cheaper intermediate exists: memoize `pngData()` alongside the existing
version-keyed `renderToUIImage()` cache, which gets most of the win without changing *what* gets
written. If the full version is ever built, it must fail closed — re-encode when unsure.

---

## 6. Open questions

Two of these were put to the owner on 2026-08-18 and are answered. The rest are open, and each is
recorded with the measurement that would close it rather than as a topic.

### Answered

**Is the "freeze on return" a jetsam kill or the app's own main-thread work? — ANSWERED 2026-08-18:
the app's own work.** *"Exactly where I left off"*, so the process was never killed. Full reasoning
in §2 item 1; the fix is item 1 and the defect is in [BUGS.md](BUGS.md). Items 12, 13 and 14 lose the
urgency the jetsam hypothesis gave them.

**Why does the owner report 17 fps when the area model predicts ~98? — ANSWERED 2026-08-18: the
report was taken at 4096×4096.** No contradiction to explain; the area model holds. The ambiguity
existed only because [BUGS.md](BUGS.md)'s entry did not pin the report to a canvas size. It now does.

Both cost one question and no runs, and both overturned something a code-tracing pass had inferred.
**Ask before building** — that is now three times the owner's behavioural report has beaten an agent
reading code.

### Still open

**What does opening a real project actually cost?** Nobody can say whether it is 200 ms or 4 s. *The
measurement*: item 9(a). This is the largest unmeasured quantity in the app.

**What does one cel's PNG encode cost at 2048×1024?** The entire "leave to gallery" ranking rests on
order-of-magnitude reasoning. *The measurement*: a `PerfBaselineTests` case timing `writePackage`
(`ProjectStore.swift:363-471`) on a realistic multi-cel document, split per cel.

**What is the true per-touch-move cost at 2048×1024?** §1, §2 item 6 and item 11's win all lean on
one extrapolated line through two MEASURED points. *The measurement*: item 8, plus a Release run on
the owner's iPad. Simulator numbers are worthless here.

**Does Core Animation actually pay for the non-native pixel format, and where?** Whether the mismatch
is a background IOSurface conversion, a lazy decode at commit-prepare on the calling thread, or
nothing meaningful is not answerable by reading code. *The measurement*: one Instruments Core
Animation "Color Copied Images" pass on the device. Until it comes back, see §5.

**Does undo history ever approach its 300 MiB cap in real use?** *The measurement*: sample
`UndoHistory`'s summed cost at the end of a real session on the device, or after a scripted sequence
of Select/Move/Fill-selection operations.

**What is the real cache occupancy at background time?** Item 12's ~384 MiB is a budget ceiling, not
an observation. *The measurement*: sample `residentBytes()` and the upload-cache counters immediately
before backgrounding, on the device.
