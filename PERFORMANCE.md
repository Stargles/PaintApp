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
live-stroke refresh at 4096² and 16.4 ms at 2048², both MEASURED on the owner's iPad 9 in Release.
Fitting `fixed + k·area` through those two points gives **~10.2 ms at 2048×1024** — about 98 fps in
isolation, not 19 (INFERRED). That is still ~61% of a 60 Hz frame budget, on the most
latency-sensitive path in the app, so it is worth fixing. It is not the app's top bottleneck and it
should not be the first thing anyone opens.
*Fixed 2026-08-20 by item 11, and the fit is retired by item 8's third point — 8.0 ms measured where
10.2 was extrapolated. The paragraph stands as written because it is the reasoning that ranked the
work, and because the device figure for the fixed path has still not been taken.*

**The "~3 s to leave to the gallery" is not the thumbnail composite.** That figure was taken against
the full 4K canvas. At 2048×1024 the thumbnail's over-render extrapolates to tens of milliseconds
(INFERRED). The multi-second wait is the whole-document PNG re-encode that navigation gates on
(`ProjectStore.writePackage`, called from `ContentView.swift:47-54`), and that cost scales with
**cel count**, not with area. Fixing only the pre-flagged thumbnail would leave the complaint intact.
*Confirmed 2026-08-20 by item 15, which is the first time either half was measured.* The re-encode is
**95% of the wait** (455 ms of 480 on a 32-cel document) and the cost is flat at **15.0 ms a cel**
across a 4× range of documents, so the scaling claim holds as written. The snapshot the thumbnail
lives in is **2.5 ms**. Item 15 then took the wait to 117 ms; ~3 s on the owner's iPad is a ~150-cel
document at the old rate (INFERRED).

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
| Save re-encodes every PNG in the document | O(cel count) × per-PNG size — measured, and no longer serial (item 15) | `ProjectStore.writePackage` |
| Load decodes and rasterizes every cel | O(cel count) — no longer serial, and no longer on main for the gallery's open (item 9) | `ProjectStore.load` / `loadInBackground` |
| `UndoHistory.maxCost` | Was a hardcoded literal; device-derived as of item 13, still canvas-independent | `UndoHistory.swift` |
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
synchronously on `@MainActor` (`ProjectStore.SaveSnapshot.init`, `ProjectStore.save`) that composites the **whole canvas**
to make a 320×320 tile (`:261-265`), *before* `beginBackgroundTask` is even requested at `:303`, then
a full-document PNG re-encode enqueued behind it. Three of those compete for the A13's cores per
switch.

The owner's second sentence allows that a few seconds may be expected. It is not — three full
document saves per switch, one landing while they watch, each compositing 2 M pixels for a 102 k tile
on the main thread *before* the background-time request that was meant to cover it. That is the
"something bad in the backend" their sentence left room for. Mechanism READ-confirmed; the
multi-second magnitude INFERRED, and corroborated by the owner reporting the symptom.

**Both halves are now fixed, and this paragraph is kept as the diagnosis rather than as a live
defect.** `ScenePhaseSaveGate` (2026-08-18) makes it **one** save per switch, on the way out —
`ProjectSaveLogicTests.testOneAppSwitchRoundTripSavesExactlyOnce` replays the phase sequence and
asserts 1. And the one save left composites **320×160** instead of the whole canvas (item 5,
2026-08-20). What remains unknown is whether one cheap save on the way out is still a felt pause on
the owner's own document — that needs their iPad, not another read of this code.

**2. Tapping a project in the gallery and the app going dead.** `ProjectStore.load` is `@MainActor`
and fully serial (`ProjectStore.load` as it then was): per cel, a PNG decode, then `RasterLayerTexture`
forces a full canvas-sized `CGContext` allocation and draw (`RasterLayerTexture.swift:196-203` →
`:235-247` → `:218-231`), then line **673** runs `regenerateAllThumbnails()` — a second full walk,
guaranteed cache-cold because every fresh texture is a new object identity at version 0.
`GalleryView.open(_:)` called it inside a Button action with no `Task`, no loading state, no
`ProgressView` anywhere. The cost is driven by cel count, so it does not shrink at 2048×1024.
Plausibly 1-3 s of hard-frozen UI on a hundred-cel project — INFERRED, and **still completely
unmeasured**; it is the first thing that happens every session.

**Item 2 shipped a spinner, 2026-08-20, and that is all it did.** The wait was the same length; it
merely looked like a wait rather than like a crash.

**Item 9 then measured it and shortened it, the same day, and the paragraph above is kept as the
diagnosis rather than as a live defect.** MEASURED: a 32-cel document at 2048×1024 opened in
**303.6 ms** — 207.3 ms of decode, 96.3 ms of thumbnails — so the guess of "1-3 s on a hundred-cel
project" was high by roughly 2-3×, and the real figure is **~0.95 s at a hundred cels** (INFERRED,
linear in cel count). It is now **53.5 ms** for the same document and **~0.17 s** at a hundred cels:
the decode fans out over cores and off the main thread, and the thumbnails happen after the canvas is
up. Full provenance in item 9. **What is still unknown is the same thing as everywhere else here** —
these are simulator figures on an 8-core Mac, and an A13's 2+4 cores will not divide by four.

**3. Leaving to the gallery. — MEASURED and shortened 2026-08-20 (item 15); this paragraph is now
the diagnosis rather than a live defect.** Navigation waits on the full write
(`ContentView.swift:47-54`), which re-encodes every PNG in the document regardless of what changed.
Encoding is correctly off-main on `saveQueue`, so nothing freezes — the artist simply waits.

**It was 480.3 ms for a 32-cel document at 2048×1024**, of which **455.2 ms was `pngData()`**, 11.7 ms
was the file I/O and 2.5 ms was the snapshot the thumbnail lives in — so **15.0 ms a cel**, flat from
8 cels to 32, or **~1.50 s at a hundred cels** and **~1.95 s on the owner's iPad 9** (INFERRED). The
owner's "~3 s" is a ~150-cel document at that rate; it needed no other explanation.
**It is now 117.1 ms for the same document, ~0.37 s at a hundred cels**: the per-cel encode runs
across cores. Full provenance, the alternated-in-one-run proof and the two unchanged control phases
are in item 15. **What is still unknown is the device multiplier** — an A13's 2+4 cores will not
divide by four.

**4. Scrubbing the timeline, and playback dropping frames. — both gates now exist.** Two ungated
main-thread costs used to fire on the same `currentFrame` write. `relayout()` ran on every SwiftUI
pass with no equality gate, redrawing the ruler and re-diffing every cel row; `TimelineLayoutKey`
gates it as of 2026-08-20, with a playhead-only fast path so a scrub moves two view frames and
invalidates nothing. `updateOnionSkin()` was the only render path in `CanvasView` without a key gate;
`OnionSkinKey` arrived with `tmp/onion`. Scrubbing drives both harder than playback does, since
`onScrub` fires unthrottled on every `.changed` sample. **Magnitude still unmeasured** — see item 3
for why a millisecond was not taken and what the counts say instead.

The cost that replaced them as the tick's main-actor headline was the sandwich **snapshot**: 78.2 ms
for six layers at 2048×1024 when the playhead moves to a new frame (MEASURED, simulator/CoreGraphics
— see item 4b). **Item 9(b) took that to ~22 ms on 2026-08-20** by spreading the per-cel flatten over
cores, so it is no longer the tick's headline; the three composites, at 22.4 ms and off the main
thread, are now the same size as it. Nothing on this tick is unmeasured any more, and none of it is
the timeline's.

**5. Playback stuttering on documents with a mask, blend mode, or grade.** `startSandwichRebuild`
still computes `below` and `above` unconditionally even though they are shown only while `midStroke`
is true — item 4b explains why that was measured and left alone, and item 4a removed the third
composite on a layer switch. Every playback tick, scrub tick and undo still computes two composites
nobody sees. It runs off-main on `sandwichQueue`,
so it burns cores rather than freezing the UI — but `isSandwichRebuilding` serialises, so a rebuild
slower than the frame interval drops frames. A six-layer sandwich rebuild at 2048² costs **54.8 ms
warm on Metal, 64.7 ms on CoreGraphics** (MEASURED, iPad 9, Release, `Compositor.swift:36`) against a
41.6 ms budget at 24 fps: it already misses. Only fires where `needsCompositorOnCanvas` is true; a
flat stack stays on Core Animation and pays none of it.

**6. Drawing on a vector layer feeling heavier than raster. — FIXED 2026-08-20 (item 11), and the
device has not confirmed it.** It was ~10.2 ms vs ~2.8 ms per touch-move at 2048×1024 (INFERRED from
the two MEASURED points in §1); item 8 then measured the real thing at 8.0 ms, and item 11 took it to
2.2 ms against the raster path's 2.1 ms — MEASURED, simulator/CoreGraphics, machine idle, table in
item 11. The gap this entry is about is gone on the simulator at all three canvas sizes.
**What is not established is the artist's experience of it.** This was one term of a frame, and items
4, 5 and 9(b) are the others; whether the owner's 4096² document now draws at something other than 17
fps is a question only their iPad answers, and it is open in §6.

---

## 3. The programme

Three tiers. Tier A is work that is correct on its own terms and cheap enough not to need a
measurement first. Tier B is instruments — the point is to stop guessing. Tier C is real, recorded,
and deliberately not urgent.

### Tier A — built 2026-08-20

**Six of the seven are on `main`, and the seventh was already there.** What follows is what each one
turned out to be, kept rather than deleted because several of the estimates below were corrected by
building the thing. Item 4 is the one that did not ship whole, and its second half is now **declined
on a measurement rather than deferred on a risk** — see it.

**1. Make the `scenePhase` save guard direction-aware. — ALREADY DONE, 2026-08-18** (commit
`1cbec5b`, `ScenePhaseSaveGate.swift`). This document and [BUGS.md](BUGS.md) both described it as
outstanding for two days after it shipped; that lag is the finding, not the fix.
*Does it really remove two of the three saves?* Yes, and `ProjectSaveLogicTests` proves it by
replaying the phase sequence SwiftUI delivers rather than by asserting on the predicate:
`testOneAppSwitchRoundTripSavesExactlyOnce` runs `[active, inactive, background, inactive, active]`
and asserts **1**. `testTheDirectAndForegroundPathsEachSaveOnce` covers the routes that skip
`.inactive`, `testASecondDepartureSavesAgain` pins that the gate is stateless, and
`testTheSaveGateMatrixIsExhaustive` pins that all nine ordered pairs are covered — a matrix is only a
contract if it is the whole matrix.
*Still wants the owner's iPad.* The count is now provably 1; whether **one** save on the way out is
still a felt pause on their document is a question only they can answer, and item 5 below is what
makes that one save cheaper.

**2. Give project open a loading state. — SHIPPED** (`GalleryOpenState.swift`, `GalleryView.open`,
`GalleryTileView`). The spinner is on the tapped tile rather than over the grid, because "which
project" is half the feedback, and `.disabled` covers the New Canvas button and the toolbar too.
*Win*: removes the "it crashed" reading of §2 item 2. It does **not** make the load faster — items 8
and 9 do that.
*What the build added to the plan.* The `Task` is the smaller half. `await Task.yield()` is the
mechanism: setting the state marks the view dirty, SwiftUI renders at the end of the current
run-loop turn, and the yield resumes after it — so the spinner is committed before the load takes
the main thread. Awaiting nothing would set the state and block in the same turn, and the artist
would see exactly what they see today.
*And a spinner creates two rules that are silent when wrong*, which is what `GalleryOpenState` is
for rather than the spinner itself. **One load at a time**: a frozen app invites a second tap, and
two loads is two `CanvasManager`s racing with the last to finish winning — a lottery between two
projects rather than a slow open of one. **Every load ends**: `ProjectStore.load` returns nil for a
package whose manifest will not decode, so a release-on-success would answer a *damaged file* with a
spinner that never stops, reporting a hang for something merely broken.

**3. Gate `TimelineTrackView.relayout()` behind an equality-checked key, and clip the ruler to its
dirty rect. — SHIPPED** (`TimelineLayoutKey.swift`, `TimelineRulerClip`). The third use of the
`SandwichKey`/`InterpolationPreviewKey` idiom, and its rules travelled with it.
*Win*: identical at 2048×1024 to what it would be at 4K, which is the point — the clearest member of
the area-independent category. Still **unmeasured in milliseconds**, and deliberately so: see below.
*`currentFrame` is the one input left out of the key.* The playhead is its own subview and a scrub
moves nothing else on the track, so it gets a two-frame fast path. Keying on it would move the key on
every sample of the one gesture that drives `relayout()` hardest — `onScrub` fires on every
`.changed` with no throttle.
*The correction the build made, and it belongs here rather than in a commit message.* **This is a
constant-factor win, not an asymptotic one.** Building the key is itself O(total cels): it walks the
same cels and pays the same folder-span flat-map. What it does not pay is the view mutation, the
per-cel interpolated accessibility identifier, the sort, the animation bookkeeping and the ruler's
CoreText — those are the expensive terms. Only the scene-length term is removed outright, and by the
gate rather than by the clip.
*And the ruler clip on its own buys less than it reads.* UIKit hands `draw(_:)` a full-bounds rect
when the whole view is invalidated, which is the common case today, so the clip is not what removes
the 300 CoreText layouts — the gate is, by removing the invalidations. What the clip buys is that
the cost becomes proportional to what is being redrawn, so a tiled backing store on a long track, or
a future `setNeedsDisplay(_:)` scoped to one column, is cheap rather than silently costing the whole
scene. `TimelineRulerClip` keeps one frame of slack each side: a label is drawn at its column's left
edge + 2pt and can overhang, so a clip taking only the columns whose origins fall inside the rect
drops exactly the two at the boundary, and the failure mode of a clip is a hole.
*Verified*: 19 headless tests, each a pair — change one thing about the document and assert the key
moved, or, for the playhead, that it did not. Plus `TimelineGestureUITests` (10) and
`UndoAndLayerHistoryUITests` (6) green, which is what says a gated relayout still lays out.
*The timing this document asked for was not taken, on purpose.* A synthetic `relayout()` timing needs
`TimelineTrackView.Coordinator`, which is a `UIViewRepresentable` coordinator and not reachable
headlessly; and a millisecond taken on this Mac is the least trustworthy number available (CLAUDE.md
records contention making suites return wrong answers). The counts are the honest instrument here.

**4a. Cache `full` across a pure `activeLayerIndex` change. — SHIPPED** (`SandwichFullKey` in
`RenderRequest.swift`, used by `CanvasView.startSandwichRebuild`). `SandwichKey`'s own comment named
this fix and declined it — "worth the wasted composite rather than a second key and a second cache to
keep them apart" — and what changed is the accounting, not the argument.
*Why it is sound*: `makeSandwichRequests` reads `activeLayerIndex` in exactly one place, the
`split(atLeaf:)` that makes `below` and `above`. `full` is the whole tree, uncut. Pinned by
`testFullIsTheSamePictureWhicheverLayerIsActive`, pixel-identical over every index on a document with
a blend in it.
*Why the second cache is free*: the image handed back is the one `sandwichImages` already retains,
and it is passed through un-rewrapped so `updateSandwich`'s `!==` checks still read "nothing changed".
*Verified*: the call count this document asked for. `CompositeProbe` (new, in `Compositor.swift`)
records every composite and its size; `testALayerSwitchCompositesTwiceRatherThanThreeTimes` asserts
**2 where there were 3**, all the same size.
*Sized properly for the first time*, and it is a bigger fraction than the old estimate implied — see
4b's table, where a layer switch turns out to be snapshot-warm and therefore almost entirely
composite.

**4b. Compute `below`/`above` lazily. — DECLINED, on a measurement.** Not deferred on risk: the
number that justified it was arithmetic over a per-layer slope, and taking the real one changes the
answer.

`testHowASandwichRebuildSplitsBetweenFullAndTheTwoHalvesAtTheOwnersCanvas` (`PerfBaselineTests`) is
the instrument. **MEASURED 2026-08-20, iOS 26.5 simulator on the 8-core MacBook, CoreGraphics backend
pinned, six layers at 2048×1024, machine 96.7% idle with no other `xcodebuild` running:**

| term | ms |
|---|---|
| snapshot, memo cold (a playback/scrub tick — a new frame) | **78.2** |
| snapshot, memo warm (a layer switch — same frame) | **0.1** |
| `composite(full)` | 11.0 |
| `composite(below)` | 6.7 |
| `composite(above)` | 4.5 |
| the three composites together | 22.2 |

These are simulator figures on the *reference* backend, so read the ratios and not the absolutes; the
device is ~1.3× (§1) and ships `.automatic`.

**Two things fall out, and the second is why 4b is declined.**

*A layer switch is snapshot-warm.* `PixelOps.rasterize` is memoized on cel identity and the playhead
has not moved, so the `@MainActor` half is 0.1 ms and the rebuild is essentially its three
composites. 4a therefore skips **half** of a layer-switch rebuild (11.0 of 22.2), not a fifth.

*A playback or scrub tick is snapshot-cold, and the snapshot is the story.* 78.2 ms on the main actor
against 22.2 ms of background composite. Making the halves lazy removes 11.2 ms — **about 11% of a
~100 ms tick, in the half that was never on the main thread** — in exchange for a stroke whose first
frames have no visible ink, on the most latency-sensitive path in the app. This document previously
put that trade at "from missing the 24 fps budget to fitting inside it", from `6 × 2.4 + 7.0 ≈ 21 ms`
(INFERRED). That estimate was not wrong about `full`'s share of the *composites*; it was wrong about
the composites' share of the *tick*.

**What this promotes instead: the snapshot.** 78.2 ms of main-actor work per playback tick is a
larger, unconditional cost sitting in front of the one 4b was aiming at, and it is item 9(b)'s
territory (`renderSources` is the same per-cel rasterize fan-out `ProjectStore.load` runs serially).
Anyone returning to 4b should do 9(b) first and then re-take this table — if the snapshot moves off
main, the composites become the tick's critical path and 4b becomes worth its risk again.

**Item 9(b) landed the same day and the table was re-taken. 4b stays declined, and for a better
reason than before.** MEASURED 2026-08-20, same test, same canvas and backend, two runs at 79–81%
idle with no other `xcodebuild` and no other booted simulator:

| term | before 9(b) | after 9(b) |
|---|---|---|
| snapshot, memo cold | 78.2 ms | **23.9 / 21.2 ms** |
| snapshot, memo warm | 0.1 ms | 0.2 ms |
| `composite(full)` | 11.0 | 11.4 / 11.5 |
| `composite(below)` | 6.7 | 6.6 |
| `composite(above)` | 4.5 | 4.4 |
| the three composites together | 22.2 | 22.4 / 22.6 |

**The three composites are the control** — unchanged code, within 4% — which is what says the two runs
are about the same machine and the snapshot's 3.5× is about the code.

A cold tick is now **~22 ms on the main actor and ~22 ms of background composite**, not ~100 ms. The
halves are 11.0 ms of the 22.4, so lazy halves would now remove **half the composites and a quarter of
the tick** rather than 11%. That is a genuinely better trade than the one declined above — and it is
still declined, because the thing being bought has changed: at 2048×1024 the background rebuild now
**fits inside the 41.6 ms budget at 24 fps with room to spare**, so the halves are no longer costing
frames, and the price is unchanged (a stroke whose first frames have no visible ink, on the most
latency-sensitive path in the app). Revisit it if a document is found that misses the budget *after*
9(b) — the 4096² stress case and the iPad's ~1.3× are where to look.

**5. Give `makeRenderRequest` a render-size hint. — SHIPPED** (`fittingWithin:`, and
`RenderRequest.renderSize(fitting:within:)`). Applied at one call site, the thumbnail composite in
`ProjectStore.SaveSnapshot`; nil everywhere else, which is native and byte-for-byte as before.
*Win, now MEASURED as a size rather than inferred*: the save's composite was **2048×1024 and is now
320×160** at the owner's canvas, asserted by `testTheProjectThumbnailCompositesAtTileSizeRatherThanCanvasSize`
via `CompositeProbe`. That is 2,097,152 pixels for the 51,200 the tile occupies — **41× the pixels**,
on the main actor, inside every save. (This document said "20× waste" for a 320×320 tile; the tile is
320×160 on a 2:1 canvas, so the ratio is twice what was written.) At 4096² it was 16.8M for 102,400.
*Why the ratio is what matters*: the absolute cost is tens of milliseconds for a plain document
(INFERRED) but several hundred once the stack carries an effect — six *faded* levels cost 1071.7 ms
against 41.6 ms flat, roughly 25× (`PerfBaselineTests`; MEASURED at 2048² on CoreGraphics, no device
or Release provenance, so take the ratio).
*What the build added*: the hint is a **bounding box, not a size**. The caller knows the box it is
filling and has no business also deciding which dimension binds — getting that wrong is silent,
because a request whose `canvasSize` has the wrong aspect composites a stretched picture that still
looks like a picture. So the fit rule is written once and is the same `min` of the two ratios
`ThumbnailRenderer` uses, and `ProjectStore` passes one named constant to both. Clamped at 1× (a hint
may only ask for less), then capped by `CompositorBudget.affordableSize`.
*Verified*: the size rule alone (aspect, both binding dimensions, the clamp, whole pixels, degenerate
inputs); the probed save; and the two tiles compared, since a saving that changes the picture is not
a saving — a mean-channel-difference bound rather than byte equality, because the two paths filter in
different places and demanding they agree exactly would be asserting something other than the claim.

**6. Wire `MaskResolver.clearCache()` to the memory-warning notification. — SHIPPED**
(`MaskCache.init`). One `addObserver` block, `PixelOps.RasterizeCache.init`'s verbatim.
*Win*: ≤16 MiB at 2048×1024 (8 entries, 1 byte/px coverage, ~2 MiB each — INFERRED). Small; the
≤128 MiB figure that makes this look important is a 4096² number.
*Verified*: a pair, because either half alone proves nothing. A control resolve that must return the
**same** `ResolvedMask` object (`==` is `===` on that type, deliberately, so identity reads the
cache); then the notification; then a resolve that must return a different one, with the same
coverage bytes. Without the control a resolver that never cached would pass; without the miss an
observer that was never registered would.
*One correction to the entry below*: the app held **three** `addObserver` calls before this, not two
— `OnionSkinSource.swift:936` arrived with `tmp/onion`.
*Why do it anyway*: `MaskResolver.swift:133-135`'s doc comment says the method exists "for a memory
warning", and **every call site in the repo is a test** — verified by grep across the whole tree, and
the app contains exactly two `addObserver` calls, neither of them this one. Its real value is closing
a documented lie, not recovering bytes. This is the identical bug class that `PixelOps.swift:145-149`
records having already been found and fixed once. Now also in [BUGS.md](BUGS.md).
*Safety*: `ResolvedMask` is fully re-derivable; two existing observers establish the pattern.
*Verified*: headless — post the notification, assert a fresh resolve.

**7. Merge `tmp/onion`. — ALREADY DONE** (commit `c97ee93`, "Close out tmp/onion"). `OnionSkinKey`
is on `main` (`CanvasView.swift`), as is `OnionSkinSource.swift` with its own memory-warning
observer. Nothing was rebuilt; the item was checked before anything was written, which is what the
plan asked for.
*Note that survives*: this is a fifth static memory budget on top of the four in item 13, and that
reconciliation is still owed.

### Tier B — measure before building

**8. Add a 2048×1024 case to the vector-vs-raster preview perf test. — SHIPPED 2026-08-20**, as its
own commit ahead of item 11 so the baseline exists in history whatever happened to the risky half.
One more call to `costs(at:)` inside `testTheLayeredLiveStrokePreviewCostsWhatTheRasterPathCosts`,
which measured 2048² and 4096² and nothing between.
*What it replaced*: the two-point linear fit `fixed + k·area` that §1 and §2 item 6 both leaned on,
which predicted ~10.2 ms/dab at the owner's canvas. Measured: **8.0 ms** on the simulator, for the
code as it stood before item 11. See item 11 for the table and for what the simulator is and is not
worth on this particular path.
*Still device-only, in one respect.* The original entry said a simulator figure was worthless here.
That was too strong and item 11's before/after shows why — this path is CPU-side, and the simulator
lands within 14% of the iPad 9 on it. What genuinely still needs the owner's hardware is the *frame
rate* claim: whether 17 fps is now something else on their 4096² document. Nothing here can answer
that, and no arithmetic over these numbers should be presented as if it had.

**9. Instrument project open, then move its decode off `@MainActor`. — ALL THREE STAGES SHIPPED,
2026-08-20.**

**Every figure below is MEASURED on `perf9-1`** — an iOS 26.5 simulator (iPad Pro 13-inch M4) on the
8-core MacBook, **Debug** build, CoreGraphics backend, the owner's 2048×1024. Two provenances are
involved and they are kept apart. The *before* row was taken at **96.7% idle** with no other
`xcodebuild` and no other booted simulator; the *after* rows come from two runs at **79–81% idle**,
also with no other `xcodebuild` and no other booted simulator. **The two are comparable, and that is
checkable rather than asserted**: the thumbnail walk is unchanged code and reads 96.3 ms in the
before run against 90.1/92.1 ms in the after runs — 5%, which is the error bar on everything here.

**(a) The instrument, and the answer to §6's oldest question.** `ProjectStore.LoadProfile` splits one
`load(from:)` into the per-cel decode and `regenerateAllThumbnails()` and carries the cel count, so a
figure can be scaled to a document of another size; `PerfBaselineTests.testWhatOpeningAMultiCelProjectCosts`
writes a four-layer, eight-cel-per-layer document with real ink on every cel, saves it, and opens it
back. **Opening a 32-cel project cost 303.6 ms** — **207.3 ms** of decode and **96.3 ms** of
thumbnails, **9.5 ms per cel**.

**So it was neither 200 ms nor 4 s: it was about a second for a hundred cels** (INFERRED at that
per-cel rate, which is what the loop bound makes linear), or ~1.2 s on the owner's iPad 9 at §1's
~1.3× (INFERRED). Nearer the bottom of the guessed range than the top — and **the thumbnail walk was
a third of it**, which is what made (c) worth building rather than an afterthought.

**(b) The fan-out is parallel, and off main for the gallery.** `PixelOps.parallelMap` is the one
primitive for the two per-cel walks, which are the same walk; `ProjectStore.loadInBackground` runs
the decode on a queue of its own so the spinner item 2 shipped can animate rather than merely have
been drawn. `load(from:)` still blocks, for the twenty-odd tests that read the result on the next
line.

| fan-out, alternated serial/parallel in one run | serial | parallel | |
|---|---|---|---|
| decode, 32 cels | 162.0 ms | **41.6 ms** | **3.89×** |
| flatten (`renderSources`' walk), 6 cels | 58.9 ms | **15.0 ms** | **3.92×** |

Peak footprint over the decode is **349 → 373 MB**, +7%: both walks retain every texture they build,
so the fan-out must not multiply what a load holds, and `parallelMap` drains an autorelease pool per
iteration so a worker's temporaries cannot accumulate. That is asserted, not just reported.

**`renderSources`' 78.2 ms is now ~22 ms, and the same test's own composites prove the machines are
comparable.** Re-taking item 4b's table: snapshot cold **78.2 → 23.9 / 21.2 ms**, while `full`
11.0 → 11.4/11.5, `below` 6.7 → 6.6, `above` 4.5 → 4.4 — three unchanged terms within 4%. So **~56 ms
of main-actor work leaves every playback or scrub tick on which the playhead moves to a new frame.**

**(c) The gallery's open no longer waits on thumbnails.** The cels arrive with `thumbnail == nil` —
the placeholder already existed, since `TimelineTrackView`'s cell hides its image view when there is
none — and `CanvasManager.backfillMissingThumbnails()` fills them in a layer at a time, off the main
actor, installing each batch in one main-actor turn.

| what the artist waits for, 32 cels at 2048×1024 | before | after |
|---|---|---|
| decode | 207.3 ms | **53.5 ms** (cold, gallery path) |
| thumbnails, inline | 96.3 ms | **0** |
| **total** | **303.6 ms** | **53.5 ms** |
| per cel | 9.5 ms | **1.7 ms** |
| thumbnails, after the canvas is up | — | 23.8 / 24.3 ms |

**5.7× on the wait itself**, and the thumbnail work that remains is 3.8× cheaper too because the
backfill uses the same fan-out. At a hundred cels that is **~0.95 s → ~0.17 s** (INFERRED, linear in
cel count).

**Two honest qualifications.** The 3.9× is on **8 cores**; the owner's iPad 9 is an A13 with 2
performance and 4 efficiency cores, so expect meaningfully less there — the shape of the win
transfers, the multiplier does not (INFERRED). And the first load in a process faults in a fresh
canvas-sized bitmap per cel: cold is **53.5 ms** against **39.4 ms** warm on a quiet machine, about
1.4×. Under host load that same gap read ~280 against ~130 ms, which is why every figure here says
what the machine was doing.

*Safety*: (a) was test-only. (b) preserves cel order explicitly rather than by completion order —
`activeCelIndex` scans that order — and `LoadProfile.decodedOnMainThread` makes the threading claim a
test assertion rather than a doc comment. (c) is arranged around a **stale** thumbnail rather than a
missing one: missing is loud, stale is a picture of the drawing as it was before a stroke, so every
install re-resolves layer and cel by id and compares a `LayerContentVersion` captured *before* the
render against the live one.

**10. Measure the Mode 3 eraser (`cutToIntersection`) live-drag cost. — MEASURED, 2026-08-20.**
`recordVectorSample` calls `resolveIntersectionCut` on **every** sample
(`StrokeCanvasView.swift:905-923`, the call at `:921` — line numbers moved since this item was
written, the mechanism did not); on a cut, `VectorCanvas.cutToIntersection` calls `invalidate()`
(`VectorLayer.swift:652` → `:389-393`), nilling the cached image, so the next `refreshDisplay`
re-stamps every stored stroke in the layer through `BrushStamper`. The cost is O(total dabs),
completely independent of canvas resolution.
*Why it is here at all, honestly stated*: this item's original motivation was that it was the leading
hypothesis for why the owner's 17 fps report did not fit the ~98 fps the area model predicts at
2048×1024. **That hypothesis is no longer needed** — the report was taken at 4096² (§6), and the area
model holds. What survives is narrower and still true: an O(total dabs) cost on a per-sample path is
structurally invisible to every area-scaled benchmark in the repo, and nobody had ever looked at it.
*The number.* `testCutToIntersectionLiveDragCostPerSample` (new, `PerfBaselineTests.swift`) reuses
`eraseScenePaintStrokes()` unchanged — the same 200-stroke, ~150-element-after layer
`testEraseHeavyVectorLayerCostAndMemory` measures — and drives a dense 334-sample vertical drag down
one column (every 6pt, denser than any hand-authored gesture fixture in this file, matching a real
touch stream) through `VectorCanvas.cutToIntersection` and `VectorEraser.IntersectionDriver`
verbatim, timing `render()` after every sample and bucketing by outcome.
**MEASURED, iOS 26.5 simulator (`perf1012-1`, iPad Pro 13-inch M4 simulated), CoreGraphics
(`VectorCanvas.render()` always uses `UIGraphicsImageRenderer` — this path has no Metal variant to
pin), isolated run (`-only-testing` for this one test, no other `xcodebuild` process alive per
`pgrep`, though general Mac CPU was 14–60% idle rather than fully quiet — three other agents were on
this Mac in adjacent worktrees running non-`xcodebuild` work):**

| outcome | mean `render()` cost | count of 334 samples |
|---|---|---|
| `.missed`/`.unchanged` (cache hit) | **0.0 ms** | 284 |
| `.cut` (cache invalidated, full re-stamp) | **94.6 ms** | 50 |

A same-scene run inside the full fast-tier suite (contended — queued behind other agents' builds)
read 114.7 ms for the same 50-cut bucket, corroborating the same order of magnitude under worse
contention; the isolated 94.6 ms is the more trustworthy of the two and is what the table reports.
Take this as an order-of-magnitude figure, not a decimal-precision one — the machine was not the
96.7%-idle standard item 4b's table used, and this path was not re-taken idle before writing it down
given the queueing three concurrent agents already imposed.
*What it means*: a cache hit is free; a cut sample costs essentially the whole re-stamp of a
~150-element layer, ~95 ms, on a canvas-resolution-independent path. A real Mode 3 drag crossing
several strokes therefore pays this once per crossing, not once per gesture — the drag measured here
paid it 50 times in 5.2 s of simulated dragging, i.e. roughly a fifth of the wall-clock time of the
gesture was spent re-stamping a layer whose *content* did not need to change on 49 of those 50
occasions (only the underlying geometry did; the cache is coarser than the edit).
*Win if fixed*: unmeasured — any fix (finer-grained invalidation, or re-stamping only the changed
region) touches three-mode eraser machinery rewritten hours before this measurement was taken
(`tmp/crosseraser`), and this item's brief was explicitly measure-only. **Do not fix it now.**
*Where it ranks*: real and now quantified, but narrow — it fires only mid-Mode-3-drag, over a layer
with enough accumulated geometry to make a re-stamp expensive, and only on the samples that actually
cross a stroke. It is not a floor on every frame the way the sandwich snapshot (item 4b/9(b)) is.
**9(b) is now done (2026-08-20) and this is the item that gains most by it**: at 94.6 ms a cut sample
is four times the whole cold sandwich rebuild, so it is the largest single-frame cost left anywhere in
the app. Scope a fix once the eraser rewrite has settled.
*Verified*: `testCutToIntersectionLiveDragCostPerSample`, `PerfBaselineTests.swift`.

**15. Instrument the save the gallery waits on, then fan its encode out. — BOTH STAGES SHIPPED,
2026-08-20.** The other half of "leaving to the gallery takes ~3 s"; §6 asked for exactly this run
and had asked since the document was written.

**Every figure below is MEASURED on `save-gallery-1`** — an iOS 26.5 simulator (iPad Pro 13-inch M4)
on the 8-core MacBook, **Debug** build, CoreGraphics, the owner's 2048×1024, raster-only cels with
real ink. Before and after were taken **minutes apart on the same idle machine**: `pgrep -fl
xcodebuild` empty both times, `top` at **93.7% idle** before and **93.3%** after (one other agent's
simulator was booted and idle). The `deviceName` in both xcresults is `save-gallery-1`, not a clone.

**(a) The instrument, and the answer.** `ProjectStore.SaveProfile` splits one `save(_:to:)` into the
main-actor snapshot, the per-cel walk (with the PNG encode and the file I/O summed separately inside
it), and the atomic-swap machinery, and carries `celCount` and `pngsEncoded` so a figure scales to a
document of another size. `PerfBaselineTests.testWhatLeavingToTheGalleryCosts` sweeps **three** cel
counts, because the claim under test is a slope.

| leaving the editor, 4 layers at 2048×1024 | 8 cels | 16 cels | 32 cels |
|---|---|---|---|
| **what the artist waits for** | **126.1 ms** | **270.3 ms** | **480.3 ms** |
| ms per cel | 15.8 | 16.9 | 15.0 |
| snapshot, on the main actor | 2.8 | 3.2 | 2.5 |
| per-cel walk | 117.1 | 242.5 | 467.3 |
| — of which `pngData()` | 114.2 | 235.7 | **455.2** |
| — of which `Data.write` | 2.7 | 6.4 | 11.7 |
| validate + stash + rename + prune | 3.7 | 6.9 | 7.8 |

**§1's claim is confirmed, and sharpened.** The cost *is* O(cel count): 15.0–16.9 ms a cel, flat
across a 4× range of documents (a second run on a busier machine — 64% idle — read 15.8/15.1/15.2,
which is the error bar). And it is **95% one call**: `pngData()` is 455 of the 480 ms, the file I/O
everyone assumes a save is bounded by is **2%**, and the whole atomic-save machinery §5 warns not to
rearrange is **1.6%**. The main-actor snapshot after item 5 made the tile 320×160 is **2.5 ms** —
the thumbnail half really is finished.

**So the owner's "~3 s" is arithmetic, not a mystery**: 15.0 ms a cel is **~1.50 s at a hundred
cels** and **~1.95 s on their iPad 9** at §1's ~1.3× (both INFERRED, linear in cel count). Three
seconds is a **~150-cel document** on that device — well inside what an animator has. Nothing else on
this path is big enough to be the complaint.

**(b) The fan-out.** It is `decodeCels`' problem pointing the other way, and it takes the same fix:
`writePackage` flattens the cel tree across layers, runs `writeCel` through `PixelOps.parallelMap`,
and rebuilds the manifest's cel order from the job list rather than from completion order.

| what the artist waits for | 8 cels | 16 cels | 32 cels | at 100 cels (INFERRED) |
|---|---|---|---|---|
| serial | 126.1 ms | 270.3 ms | 480.3 ms | ~1.50 s |
| over cores | **72.4 ms** | **65.2 ms** | **117.1 ms** | **~0.37 s** |
| ms per cel | 9.1 | 4.1 | 3.7 | |

**4.1× on the wait itself at 32 cels, and the proof is not that table.** Two arms alternated three
times each inside one test — the only comparison a machine that hosts several suites at once cannot
distort — read **500.3 ms serial against 96.2 ms parallel, 5.20×**, at 283.8 vs 284.3 MB peak (+0.2%:
a PNG per worker, not a bitmap per worker). `activeProcessorCount` was 8.
**The control is the two phases this did not touch**: the snapshot reads 2.5 → 2.2 ms and the atomic
swap 7.8 → 7.4 ms across the two runs, so the machines are comparable.

**One number goes the wrong way, and it is worth stating rather than hiding.** `pngData()` **summed
across workers** rises from 455.2 to 734.4 ms at 32 cels — spreading an encode over eight cores makes
each worker's own encode slower, because they contend for memory bandwidth. The wall clock is what
the artist waits for and it fell by 4×; the CPU-seconds bill rose by 1.6×, which on a battery-powered
device is a real if minor cost.

**The qualification is item 9(b)'s, unchanged.** The 5.2× is on **8 cores**. The owner's iPad 9 is an
A13 with 2 performance and 4 efficiency cores; the shape of the win transfers and the multiplier does
not (INFERRED). A hundred-cel save on that device is somewhere between 0.4 s and 1 s, and **nobody
has measured it there** — see §6.

*Safety*: (a) was instrumentation only. (b) changes **nothing about what is written** — the same
bytes to the same files, named after cel ids that are UUIDs, from `UIImage`s that are immutable and
one per worker. The failure a fan-out could introduce is a manifest assembled in completion order,
which would shuffle an artist's drawings between frames while still validating and loading; the order
is reconstructed from the job list, and `ProjectSaveLogicTests.testEveryCelsPixelsAndOrderSurviveTheParallelWrite`
pins it by giving every cel a dot at a position derived from its own index. Nothing covered that
before: every other round-trip test in that file reads `cels[0]`, and one cel per layer cannot show
an ordering.

**What was deliberately not built: the memo.** §5's entry on this path stands. Skipping the encode
for a cel whose pixels have not moved is worth far more than 4× on a document where the artist
touched three cels — but it is the data-loss class of risk, it belongs beside
`RasterLayerTexture`'s existing version-keyed `renderToUIImage()` cache rather than in a second
identity scheme in `ProjectStore`, and `SaveProfile.pngsReused` exists as the counter it would move.
*Verified*: `testWhatLeavingToTheGalleryCosts`, `testSavePngEncodeFanOutIsWorthIt`
(`PerfBaselineTests.swift`), `testEveryCelsPixelsAndOrderSurviveTheParallelWrite`
(`ProjectSaveLogicTests.swift`).

### Tier C — real, recorded, not urgent

**11. Give the `.overlay` vector scratch its own layer. — SHIPPED 2026-08-20** (`VectorPreviewPlan`,
`StrokeCanvasView.scratchView`). The `.overlay` branch flattened the committed render and the live
scratch into a fresh canvas-sized bitmap on every touch-move; `scratchView` is a sibling
`UIImageView` above the base one, and Core Animation composites the two — which it was doing to the
result anyway. Three of the four canvas-sized operations are gone: the allocation and both blits.

*Win — MEASURED, simulator/CoreGraphics, per dab, before → after.* Taken 2026-08-20 on this Mac with
**93.6% idle CPU and no other `xcodebuild` running**, which is stated because three sessions were
working this repo that night and CLAUDE.md records that contention here does not slow a suite down so
much as make it **return wrong answers**. Both shapes are measured **in the same run seconds apart**
rather than across two commits, so the ratio is immune to the machine drifting between them.

| canvas | raster path | `.overlay` before | `.overlay` after | speedup |
|---|---|---|---|---|
| 2048×1024 (the owner's) | 2.1 ms | 8.0 ms | **2.2 ms** | 3.6× |
| 2048×2048 | 2.4 ms | 16.1 ms | **2.5 ms** | 6.6× |
| 4096×4096 (the 17 fps report) | 3.6 ms | 47.1 ms | **3.9 ms** | 11.9× |

The after column *is* the raster column, within 5%, which was the whole claim: what is left is
`scratch.renderToUIImage()` and a memo hit. This path's own fps ceiling at 4096² goes **21 → 253**.

*Reproduced.* A second run an hour later, inside the whole fast tier rather than alone, on the same
device at 96.7% idle: 7.4 → 2.2, 14.3 → 2.4, 44.2 → 3.2 ms, ceiling 23 → 309. Every figure is within
8% of the table and the two runs disagree about nothing. Recorded because this repo has been burned
by single readings, and because a ratio that survives being measured twice under different loads is a
different kind of claim from one that has not been.

*Two things this does not say.* It is not a device figure — see §5 and the still-open question in §6;
a Release run on the owner's iPad is what closes it, and it is the one thing this item still owes.
And it is not a frame rate: it is one term of a frame, and items 4, 5 and 9(b) are the others.

*What the simulator turned out to be worth here, which is more than §5 would lead you to expect.* The
before column is measurable against [BUGS.md](BUGS.md)'s device numbers, because it is the same code
path: 47.1 ms simulator against **53.8 ms** device at 4096², and 16.1 against **16.4** at 2048². So
on *this* path the simulator lands within 14% and 2% of the iPad 9 — because the cost is CPU-side (an
allocation and two blits) with no GPU in it, which is exactly the condition §5's "the simulator
misreports GPU cost by more than 10×" does not cover. Do not generalise it: it is a fact about a
CPU-bound path, not a new device factor, and §1's ~1.3× still governs compositing work.

*And it retires the fit.* §1 and §2 item 6 extrapolated ~10.2 ms/dab at 2048×1024 from two points.
Item 8's third point measures the same shape at **8.0 ms** on the simulator. The fit was in the right
place and slightly high; the paragraphs that leaned on it are left standing rather than rewritten,
because the number they used is now history either way.

*Risk, and how it was discharged.* This was the highest-risk item on the board and the reasoning
stands: [BUGS.md](BUGS.md) calls this the most gesture-sensitive code in the app, and `.replacement`
(Mode 1) and `.none` (Modes 2/3) were **already** one-operation paths where a regression is not slow
ink but an eraser that shows nothing until lift. Neither gains an operation — both take an
identity-guarded `showScratch(nil)`, a pointer comparison. Three things pin it: `VectorPreviewPlan`
has **no case that can express the old composite**, so reintroducing it means changing the type;
`VectorPreviewPlanLogicTests` walks all twelve (role × scratch × interpolation) inputs in the fast
tier; and the full UI suite ran clean, with `VectorEraserUITests` asserting `.replacement` publishes
more than one live frame, `.none` publishes zero, and — new — `.overlay` publishes more than one, the
only observable difference between a scratch layer that follows the pen and one stuck on touch-down.
*Sequencing*: item 8 landed first, as its own commit, so the baseline exists in history independently.

**12. Purge the compositor and flatten caches on backgrounding, not only on a memory warning. — SHIPPED, 2026-08-20.**
`MetalCompositor.swift`'s own doc comment names the exact scenario — caches "sit at their
high-water mark … against a document nobody is looking at" when the artist switches apps — and then
(before this change) subscribed only to the one event the owner reports never arriving. Two
`didEnterBackgroundNotification` observers now call the same `purge()`/`removeAll()` that already
existed for the memory-warning case: `CompositorMetalEngine.init` (`MetalCompositor.swift`, right
after its existing memory-warning observer) and `PixelOps.RasterizeCache.init`
(`PixelOps.swift`, same spot) — both caches item 12's win figure names, not just the Metal one.
*Re-verified before writing, as asked, because a similar claim was off by one the day before this
one*: `grep -rn "didEnterBackgroundNotification" --include="*.swift" .` returned zero matches before
this change. `grep -rn "addObserver"` returned exactly four — `OnionSkinSource.swift:936`,
`MetalCompositor.swift:386` (the existing memory-warning one), `MaskResolver.swift:281`,
`PixelOps.swift:168` (the existing memory-warning one) — consistent with item 6's correction that the
app held three before *its* addition, plus `MetalCompositor`'s own. **The "no `didEnterBackground`
observer anywhere" claim held.** It now holds six: the four above plus the two new ones.
*A note on scope*: item 12's brief named only `MetalCompositor.swift`, but its own win figure
(384 MiB) is 192 MiB Metal **plus** 192 MiB flatten memo — the memo is `PixelOps.RasterizeCache`, a
different file. Purging only the Metal half would have shipped half the doc comment's promise and
half the win figure, so `PixelOps.swift` was touched too; the change there is the same three-line
shape as the existing memory-warning observer immediately above it.
*Win*: up to ~384 MiB off the background resident footprint (192 MiB Metal + 192 MiB flatten memo,
both device-derived so both at full size here). **Still INFERRED** — the budgets and the (now fixed)
missing observer are READ/shipped; real cache occupancy in a live session was not measured, and this
change does not measure it either.
*Why it moved down, and stays down*: this was sized against the jetsam hypothesis, and **the owner's
answer disconfirmed it** (§2 item 1, §6). It ships as cheap hygiene whose own doc comment already
promised the behaviour — a smaller background footprint is still the right thing on a 3 GB device —
**and this no longer buys a fix for a bug anyone has.** Nothing about shipping it changes that framing.
*Safety*: `purgeLocked()` is documented "correctness-neutral by construction"; the cost is one cold
composite on return. MEASURED at 2048² on the iPad 9: a six-layer sandwich rebuild is 108.1 ms cold
against 54.8 ms warm on Metal (`Compositor.swift:36-37`), so about **53 ms of one-time cost** on the
frame after a return.
*Verified*: `testEnteringBackgroundPurgesTheUploadCacheAndTheRasterizeCache`
(`CompositorParityLogicTests.swift`) — headless, a control/post/assert pair for *each* cache (either
half alone proves nothing: without the warm step a cache that was never populated would pass for
free; without the post step an observer that was never registered would too). Warms
`CompositorMetalEngine`'s upload cache via a real `MetalCompositor.composite(_:)` and the flatten memo
via `PixelOps.rasterize(cel:canvasSize:)`, asserts both non-empty, posts
`didEnterBackgroundNotification`, asserts both empty. `CompositorMetalEngine.uploadCacheEntryCount`
(new, alongside the existing lifetime `uploadCacheCounts`) and `PixelOps.rasterizeCacheBytes`
(existing) are what the test reads. Skips if no Metal device is available in the test process.

**13. Device-scale `UndoHistory.maxCost`, and reconcile the four static budgets. — SHIPPED
2026-08-20** (`UndoBudget` in `UndoHistory.swift`, the subscription in `CanvasManager.init`,
`MaskResolver.cacheEntryLimit`, `MemoryBudgetLogicTests`).

**The budget is now the device's, on the rule the item named.** `UndoBudget.maxCostBytes(physicalMemory:)`
is `min(max(physical / 16, 64 MiB), 768 MiB)` — `CompositorBudget.textureBudgetBytes`'s arithmetic
character for character, deliberately written twice rather than called, because `CompositorBudget`
carries `budgetOverrideBytes` and an undo budget that moved whenever a compositor test set it would be
a genuinely nasty coupling. `testTheThreeLargeBudgetsRunOnOneRule` pins the two equal on every device,
so the duplication is loud if anyone edits one.

**And there are five budgets, not four** — item 7 found the fifth and left the reconciliation owed.
Here they are at the owner's 2048×1024 on the owner's iPad 9, before and after:

| budget | what it holds | rule | before | after |
|---|---|---|---|---|
| `CompositorBudget.textureBudgetBytes` | GPU pool, effect intermediates, upload cache | `physical / 16` | 192 MiB | 192 MiB |
| `PixelOps.rasterizeCache` | CPU flattens, one memo before upload | borrows the line above | 192 MiB | 192 MiB |
| **`UndoHistory.maxCost`** | **before/after snapshots — user data** | **was a literal, now `physical / 16`** | **300 MiB** | **192 MiB** |
| `MaskResolver.cache` | resolved coverage, 8 entries at 1 byte/px | entry count | ~16 MiB | ~16 MiB |
| `OnionSkinBudget.residentBudgetBytes` | reduced ghost sources plus composite | flat literal | 64 MiB | 64 MiB |
| **sum** | | | **764 MiB** | **656 MiB** |

At 4096² only the mask row differs — 8 × 16 MiB = 128 MiB rather than 16, so the sums are 876 and
768 MiB. Every figure in that table is INFERRED arithmetic over the constants, and
`testTheFiveBudgetsSumToLessThanTheJetsamCeilingOnTheOwnersDevice` asserts the whole row rather than
reciting it.

**The one story they tell.** The three that are big enough to matter run on one rule, a sixteenth of
the device each. The two that do not scale say why they do not: a mask cache is bounded by how many
distinct masks one frame can plausibly carry and an onion budget by how soft a ghost may be, and
neither becomes a different question on a bigger iPad. What changed is that undo used to be the
**largest single budget in the app** — 300 MiB against 192 apiece for two caches sized from a measured
crash table — with nothing behind the difference but the literal somebody typed.

**Two honest qualifications on the ~700 MiB arithmetic this item was built on.** It is five *ceilings*
added together and nothing has ever observed them full at once (item 12 makes the same point about its
own 384 MiB, and §6 still lists real occupancy as open). And it is not the app's memory story anyway:
item 14 measures a drawn raster cel at **6.6 MiB resident**, so a 120-cel scene is ~787 MB —
**more than all five budgets together, and unbudgeted**. The reconciliation's real finding is that the
budgeted half of the app is the smaller half.

*What the cut costs the iPad 9, stated rather than glossed, because a regression in undo is one the
owner feels the same day.* It is 300 → 192 MiB there. In the two units that matter, MEASURED
2026-08-20 on `tierc-1` (iOS 26.5 simulator, iPad Pro 13-inch M4, Debug, machine 95.9% idle with no
other `xcodebuild` running), `testManySmallStrokesAllStayUndoableWithinTheBudget`:

| step | cost | at 300 MiB | at 192 MiB |
|---|---|---|---|
| small freehand stroke (cropped dirty rect) | **17,680 bytes** MEASURED | ~17,800 | **~11,400** |
| canvas-spanning stroke at 2048² | **24.9 MB** MEASURED | 12 | 7 |
| whole-cel operation at 2048×1024 (fill, clear, insert, bake) | 16 MiB INFERRED (`w·h·4` twice) | 18 | **12** |

**So for freehand drawing the cut is inert** — eleven thousand strokes is not a session — and it bites
only on whole-cel operations, 18 → 12. The cut is also self-targeting: it can only bite in a session
that has already retained 192 MiB of history, which is the session nearest the ceiling anyway.

*The pressure valve, which is what makes the smaller ceiling a net improvement rather than a
trade.* Undo was **the only one of the five with no response to a memory warning at all** — the two
large caches and the mask cache each drop wholesale, and this one sat at its high-water mark.
`trimUnderMemoryPressure()` lowers the budget to half, runs the ordinary `trim()`, and puts the budget
back, so the bytes come back now and depth grows again as the artist works; leaving it lowered would
turn one transient warning into a permanently shallow history. It trims the **oldest** and never
clears, because a cache entry costs one recomputation and an undo step costs work the artist cannot
get back. On the iPad 9 that is 96 MiB retained — six whole-cel operations — against 300 MiB that
previously could not give back a byte.
*The one judgement here that wants the owner rather than an argument is that fraction.* Half is a
guess dressed as a constant; §6 carries the measurement that would replace it.
*Safety*: pure logic, fully headless, plus one Combine subscription. The subscription is `cancellables`
rather than the caches' `addObserver` block on purpose — those three are process-lifetime singletons,
but a `CanvasManager` is per-document and the test target builds dozens, so an unremoved observer
token would leave a dead closure behind for every document ever opened.
*Verified*: nine cases in `MemoryBudgetLogicTests` — the rule against `CompositorBudget`'s on five
device sizes plus both clamps and a monotonicity check; the five-budget sum; the pressure trim as a
**pair** (a control history inside the pressured budget that must lose nothing, then one at the budget
that must lose exactly half and keep its newest step); that redo is untouched; that the budget is
restored and the history grows back; and the wiring, where a real `CanvasManager` is posted the
notification and `canUndo` must still be right afterwards.
*Note that survives*: freehand strokes are stored as cropped dirty rects
(`StrokeCanvasView.swift:528-555`), which is why the small-stroke row above is 17 kB and not 16 MiB.
Whether a real session reaches any cap is **still unmeasured** — see §6.

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

**Do not build a dirty-tracking save.** *(Both preconditions this entry named are now met — item 1
landed 2026-08-18 and item 9's instrumentation landed 2026-08-20 — so what follows is the whole of
the argument rather than a wait. **Item 15 then measured this path and took the safe 4× off it
without touching what gets written**, which lowers the pressure on this entry rather than raising
it: the encode is now spread over cores, so the memo below is worth a further ~3.7 ms a cel on the
cels that did not change, not the whole 15.)*
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

**What does opening a real project actually cost? — ANSWERED 2026-08-20 by item 9(a): 303.6 ms for a
32-cel document at 2048×1024**, 207.3 ms of decode and 96.3 ms of thumbnails, 9.5 ms a cel — so
**~0.95 s at a hundred cels** (INFERRED), against a standing guess of 1-3 s. It is now 53.5 ms and
~0.17 s for the same documents; full provenance in item 9. **The interesting part is that this was
the largest unmeasured quantity in the app for two months and the answer was three times smaller than
the guess** — the same shape as the 4K recalibration in §1, and the reason this document insists on
labels.

**What does one cel's PNG encode cost at 2048×1024? — ANSWERED 2026-08-20 by item 15: 14.2 ms**, and
it is **95% of the whole gallery-exit wait** (455.2 ms of 480.3 on a 32-cel document; the file I/O is
11.7 ms and the atomic-swap machinery 7.8). The wait is **15.0 ms a cel**, flat from 8 cels to 32 —
so §1's "scales with cel count, not with area" is confirmed rather than assumed, and the owner's
"~3 s" is simply a ~150-cel document on their iPad (INFERRED). It is now 117.1 ms for that document.
**The surprise was the ratio, not the total**: the entire ranking of this path had assumed the file
write mattered, and it is 2%.

**How much does a machine under load change a figure here? — ANSWERED, and it is worse than "slower".**
The same test, same binary, same day: `saveForReference` read 863 ms on an idle Mac, 988 ms with two
other suites running, and 3187 ms with three. The decode's cold-versus-warm gap read 1.4× idle and
~2.2× contended. A number taken under contention is not a number with a wider error bar; it is a
number about a different thing. `pgrep -fl xcodebuild` and `top -l 2 -n 0 -s 2` before, and state
what they said.

### Still open

**What is the true per-touch-move cost at 2048×1024? — ANSWERED on the simulator 2026-08-20 (item 8),
and the question that replaced it is better.** The fit said ~10.2 ms; the reading is 8.0 ms before
item 11 and 2.2 ms after, simulator/CoreGraphics. The "simulator numbers are worthless here" this
entry used to carry was wrong for this path and item 11 says why.
**The live question is now the owner's, not a run's: does their 4096² document still draw at 17 fps?**
Item 11 deleted ~43 ms of per-dab CPU work at that size on the simulator, and 53.8 ms of it was
MEASURED on their own iPad in Release. If the number has not moved on the device, the remaining cost
is somewhere this document has not looked. *The measurement*: they draw on the stress canvas and say
— and, for a figure rather than an impression, a Release build of this branch on that iPad.

**Does Core Animation actually pay for the non-native pixel format, and where?** Whether the mismatch
is a background IOSurface conversion, a lazy decode at commit-prepare on the calling thread, or
nothing meaningful is not answerable by reading code. *The measurement*: one Instruments Core
Animation "Color Copied Images" pass on the device. Until it comes back, see §5.

**Does undo history ever approach its cap in real use? — still open, and item 13 made it cheap to
answer.** The cap is now `physical / 16` — **192 MiB on the owner's iPad 9**, down from the 300 MiB
literal — and `UndoHistory.currentCost` exists precisely so this can be sampled rather than argued
about. Item 13's table says 192 MiB is ~11,400 cropped freehand strokes or 12 whole-cel operations, so
the question is really "does a session do a dozen fills, clears, inserts or selection bakes without
closing the document?" *The measurement*: sample `currentCost` at the end of a real session on the
device, or after a scripted sequence of Select/Move/Fill-selection operations.
**And the fraction the pressure valve trims to — half — is a guess wearing a constant's clothes.**
It leaves six whole-cel operations on a memory warning. Whether that is generous or stingy is the
owner's call and nothing here can make it: *the measurement* is the same sample, plus asking them how
far back they ever reach.

**What is the real cache occupancy at background time?** Item 12's ~384 MiB is a budget ceiling, not
an observation. *The measurement*: sample `residentBytes()` and the upload-cache counters immediately
before backgrounding, on the device.

**Does leaving to the gallery still feel like ~3 s?** Item 15 measured the wait for the first time and
made it 4× shorter, but every figure is a Debug simulator on 8 cores and the owner's report is a
Release build on an A13 with 2+4. Both the before and the after transfer in *shape* and neither
transfers in *multiplier*. *The measurement*: the owner leaves a real document to the gallery on their
iPad and says — and, for a figure rather than an impression, a Release build of `main` on that iPad
with `SaveProfile` read out. **Ask before building anything further here**: if it now feels instant,
§5's memo stays unbuilt for good, and if it still feels like seconds the interesting question is what
their cel count actually is.

**Is one save on the way out still a felt pause?** Tier A cut the app switch from three full saves to
one, and made that one composite a 320×160 tile instead of the whole canvas. Whether the freeze the
owner reported is *gone* or merely *smaller* is not answerable from here. *The measurement*: the
owner switching away from a real document on their iPad and saying. This is the one Tier A result
that wants them rather than a run.
