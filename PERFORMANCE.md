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
owner animates at 2048×1024** — one eighth the pixels. Asked whether it was that or 1080p, they said
"likely the former" (2026-08-17). Any cost that scales with canvas area is overstated eightfold
against the document that actually exists, and a conclusion drawn at 4K may be about a canvas nobody
uses. **Benchmark at 2048×1024 first and treat 4096² as the stress case, not the baseline** — that
applies to the 17 fps entry below, the gallery thumbnail and the onion skin composite alike.

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
lives in is **2.5 ms**. Item 15 then took the wait to 117 ms; ~3 s on the owner's iPad was inferred to
be a ~150-cel document at the old rate.
*Correction, 2026-08-21*: that inference is **refuted**. The owner's real projects were read directly
off the device (item 14) — **1–4 cels each**, not ~150 — so the ~3 s report has no cel-count
explanation and whatever caused it is unexplained. It no longer matters in practice: a Release build
of the fan-out (item 15) is on the owner's iPad now, and they report leaving the gallery **instant**.

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
up. Full provenance in item 9.
**Confirmed on the owner's iPad 9, 2026-08-21, Release build `38e22c6`: "no issues."** The visible
behaviour change — cel blocks arriving blank and filling in a fraction of a second later — reads as
loading rather than as broken (item 9(c)), which was the open question this paragraph used to carry.

**3. Leaving to the gallery. — MEASURED and shortened 2026-08-20 (item 15); this paragraph is now
the diagnosis rather than a live defect.** Navigation waits on the full write
(`ContentView.swift:47-54`), which re-encodes every PNG in the document regardless of what changed.
Encoding is correctly off-main on `saveQueue`, so nothing freezes — the artist simply waits.

**It was 480.3 ms for a 32-cel document at 2048×1024**, of which **455.2 ms was `pngData()`**, 11.7 ms
was the file I/O and 2.5 ms was the snapshot the thumbnail lives in — so **15.0 ms a cel**, flat from
8 cels to 32, or **~1.50 s at a hundred cels** and **~1.95 s on the owner's iPad 9** (INFERRED). The
owner's "~3 s" was inferred at the time to be a ~150-cel document at that rate.
**It is now 117.1 ms for the same document, ~0.37 s at a hundred cels**: the per-cel encode runs
across cores. Full provenance, the alternated-in-one-run proof and the two unchanged control phases
are in item 15.
*Correction, 2026-08-21*: item 14's direct read of the owner's device found **1–4 cels a project, not
~150**, so the ~150-cel inference above is refuted and the ~3 s report is not explained by cel count
after all — see item 15 for what that leaves open. **The device multiplier no longer matters for this
one**: the owner has since run this fan-out in Release on their iPad 9 and reports leaving the gallery
**instant**.

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
**Confirmed on the owner's iPad 9, 2026-08-21, Release build `38e22c6`: "17fps is gone, good job. 4k
screen displays full 60fps when painting."** This is the headline result of the whole performance
programme — item 11's simulator figures predicted exactly this, and the device now confirms the
ceiling sits above the display's 60 Hz. This was one term of a frame, and items 4, 5 and 9(b) are the
others, but the artist's own report is now in, and it closes this entry.

**7. Moving a whole vector layer. — MEASURED and FIXED 2026-08-21 (item 16), on the owner's report
rather than on this programme's ranking.** *"Move is extremely slow, reducing FPS to 5fps."* It is
item 11's trap on the other per-input-event path: every touch-move of a Move drag paid **two**
canvas-sized rasterizations of every element in the layer plus a multi-megapixel alpha scan, one of
them to recompute a bounding box a transform cannot change. **96.1–107.8 ms a sample at 2048×1024**
— a 9–10 fps ceiling in Debug on the simulator against the owner's 5 fps in Release on their iPad. It
is now **0.002 ms**: the live drag rasterizes nothing and Core Animation shows every delta. **The
report came off the same device pass, and the same build `38e22c6`, that confirmed painting at 60 fps
(entry 6 above)** — so a programme that had just declared itself closed on hardware was carrying a
9-fps path the whole time, on a tool the owner uses constantly. The device has not confirmed the fix;
see §6.

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

**Confirmed on the owner's iPad 9, 2026-08-21, Release build `38e22c6`: "no issues."** Both the
opening wait and (c)'s deliberate behaviour change — cel blocks arriving blank and filling in —
were checked together and read as loading rather than as broken. Accepted as designed.

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

**17. Mode 2 (`cutPoints`) live preview — the first Cut measurement that exists. — MEASURED and
SHIPPED, 2026-08-22.** Not from the ranking either; it came out of the owner asking twice for Cut to
show something while the finger is down (*"the to cut eraser does not have live feedback like the to
cross eraser, it only applies when the eraser is lifted"*). The design question was whether a preview
could be had **without** buying item 10's term: Mode 3 is live because it commits real cuts per
sample and pays ~95 ms a time re-rendering the layer cold, and copying that mechanism into Cut — which
has no `IntersectionDriver` latch, so it would fire on nearly every sample over ink — was never on.

*The number.* `testCutPointsLivePreviewCostPerSample` (new, `PerfBaselineTests.swift`) reuses
`eraseScenePaintStrokes()` and item 10's own 334-sample drag, so the two numbers share a fixture as
well as a scene, and times three candidate designs **in the same run, seconds apart**, so the ratios
between them survive whatever the machine is doing.

**MEASURED, iOS 26.5 simulator (`cuteraser`, iPad Pro 13-inch M4 simulated), 2048² canvas, 200-stroke
vector layer, Debug, CoreGraphics. CONTENDED — 25–35% idle CPU, no other `xcodebuild` alive per
`pgrep`; the load was ~2.9 cores of Adobe background processes (AdobeIPCBroker, Adobe Desktop
Service, Creative Cloud) plus WindowServer, which did not go away over the session.** Three
consecutive runs at that load agreed to **±0.5%** on every median, which is the reason these are
worth writing down at all: the per-sample work is short enough to fit inside one scheduling slice, so
it is not being sliced up the way a whole suite is.

| per touch sample | median when the sample cuts | median when it does not |
|---|---|---|
| (a) Cut as it was — no preview | **0.000 ms** (render memo hit) | 0.000 ms |
| (b) span-and-caps preview — SHIPPED | **0.426 ms** (p95 0.466) | 0.071 ms |
| (c) plain footprint punch | **0.014 ms** | ~0 |

(b) splits **0.107 ms geometry** (`cutPreviewEdits`: one spatial-index query, the `cutRanges` probe
walk, `splitStroke`, the end-cap windows) and **0.333 ms stamping** (`applyPreview`: erasing the span
and drawing the caps back) — so the dabs, not the geometry, are where it goes. Two costs are shared with Mode 1 and are **not** new
here: `renderToUIImage` off the scratch, **0.033 ms** per refresh, and the canvas-sized scratch copy
at touch-down, **7.7–11.2 ms once per gesture**.

*What it means.* (b) is 30× (c) and still **3.7% of a 60 Hz frame**, against item 10's ~95 ms — 220×
cheaper than the mechanism it was competing with. (c) was measurably cheaper and is measurably wrong:
Mode 2 does not remove its footprint, it removes a centreline span *minus* the round end caps the two
surviving pieces grow back into the gap, and those caps are large. Cut a 40pt line with an 8pt eraser
and **not one pixel changes** — the footprint punch would open a notch and hand it back on lift.
`VectorCutPreviewLogicTests` measures both against the committed cut.

*Where it ranks*: shipped, so nowhere — but it is worth keeping beside item 10 as the counter-example.
Item 10's cost is not "previewing an eraser"; it is *mutating the display list on a per-input-event
path*. A preview that reads geometry and draws into a scratch raster is three orders of magnitude
away from one that cuts for real.
*Verified*: `testCutPointsLivePreviewCostPerSample` (`PerfBaselineTests.swift`),
`VectorCutPreviewLogicTests`, `CuttingModesUITests.testCutPreviewsLiveAndToCrossStillDoesNot`.

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

**So the owner's "~3 s" looked like arithmetic, not a mystery**: 15.0 ms a cel is **~1.50 s at a
hundred cels** and **~1.95 s on their iPad 9** at §1's ~1.3× (both INFERRED, linear in cel count).
Three seconds looked like a ~150-cel document on that device.
**Refuted, 2026-08-21 — item 14's direct read of the owner's device found 1–4 cels a project, not
~150.** So the ~3 s report is *not* explained by cel count after all, and whatever caused it is
unexplained. It is moot in practice: the fan-out below has since shipped in Release on the owner's
iPad, and they report leaving the gallery **instant**.

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
**And it stays unbuilt for good.** The handoff after this item shipped said exactly what would settle
it: *"if it feels instant, §5's dirty-tracking memo stays unbuilt for good."* Owner, 2026-08-21,
Release build `38e22c6`, iPad 9: *"leaving the gallery is instant."* It does; retire the memo.

### Tier C — real, recorded, not urgent

**All four were closed 2026-08-20 — 11 and 12 shipped, 13 shipped, 14 measured and declined — and
with them the whole programme.** Fifteen items: thirteen built, item 10 measured and deliberately
left alone until the eraser rewrite settles, item 14 measured and declined at the time.
**The device pass landed 2026-08-21** — items 9, 11, 13 and 15 are now confirmed on the owner's own
iPad 9 in Release, not merely on the simulator; see each item and §6. **Item 14 alone was re-opened
by the owner's answer on what a real document is meant to hold, then re-scoped by a direct read of
the owner's actual device data** — its own entry below is rewritten in full; the cheap half it turned
up is the one thing left queued from this whole programme.

**Item 16 was added afterwards and did not come from this ranking at all** — the owner reported it
off their own iPad on 2026-08-21, on a path nothing here had ever looked at. That is worth recording
next to a programme that closed itself: the ranking above was built by reading code and reasoning
about canvas area, and a ~100 ms per-touch-move path on a tool the artist uses constantly was
invisible to all fifteen items — then found in four seconds by someone dragging something. Item 10
already says why an O(elements) cost on a per-input-event path is invisible to every area-scaled
benchmark in this repo. This is the second time that sentence has turned out to be true.

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

*Two things this did not say, and the first is now closed.* It was not a device figure — **a Release
run on the owner's iPad is what closes it, and it was the one thing this item still owed; it is now
paid, 2026-08-21.** The owner, on their iPad 9, Release build `38e22c6`: *"17fps is gone, good job. 4k
screen displays full 60fps when painting."* Item 11's simulator ceiling at 4096² was 21 → 253 fps; the
device confirms the ceiling now sits above the display's 60 Hz. And it is still not a frame rate on
its own: it is one term of a frame, and items 4, 5 and 9(b) are the others.

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

**Two honest qualifications on the ~700 MiB arithmetic this item was built on, and the second is now
corrected rather than merely a caveat.** It is five *ceilings* added together and nothing has ever
observed them full at once — item 14's rewrite finds four of the five cannot be reached at all at
2048×1024, so a defensible steady state is **~250–450 MiB**, not 656, and adding the full sum to a
cel-residency figure double-counts headroom that was never gone. And this was never the app's whole
memory story anyway: a drawn raster cel is **6.558 MiB resident, measured** (not 6.6, not "MB" —
see item 14), so a document large enough to matter is **more than these five budgets together, and
unbudgeted regardless of which of the two totals above is used.** The reconciliation's real finding
stands: the budgeted half of the app is the smaller half.

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
**Ruled by the owner, 2026-08-21: both constants are right.** 192 MiB of budget (~12 whole-cel
operations) and trimming to half on a memory warning (~6) are no longer guesses dressed as constants
— they are OWNER-STATED decisions, and the open question in §6 that asked for this is closed. A real
session's actual `currentCost` is still unsampled, but the ruling does not wait on it: the owner has
judged the sizing adequate directly rather than by having it measured and shown to them.
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

**14. Bound raster-cel residency. — RE-OPENED 2026-08-21 on the owner's answer, then RE-SCOPED
2026-08-21 on a direct read of the owner's device. The expensive half stays DECLINED; the cheap half
SHIPPED 2026-08-22.**

`RasterLayerTexture.init` allocates a full canvas-sized `CGContext` and draws the decoded PNG in
whenever an image is passed (`:196-203` → `:235-247` → `:218-231`), and `load` does this for every cel
of every layer. There is no eviction of any kind — unlike the vector tier's
`evictDistantVectorRenderCaches` (`CanvasManager+Interpolation.swift:489-511`, capped at 12 cels).

**The number, still standing.** `PerfBaselineTests.testWhatOneDrawnRasterCelCostsResidentAtTheOwnersCanvas`
builds inked cels one at a time and differences `phys_footprint`, in two equal halves so the slope can
be checked for flatness rather than assumed. **MEASURED on `tierc-1` (iOS 26.5 simulator, iPad Pro
13-inch M4, Debug), 24 cels at the owner's 2048×1024:**

| | |
|---|---|
| per drawn cel, first half / second half | **6.6 / 6.6 MiB** |
| the arithmetic this item was sized on (`w·h·4`) | 8.0 MiB |
| `renderToUIImage()`'s memo, per cel | **0.0 MiB** |

**Taken twice under deliberately different host load and it did not move** — once at 3.7% idle and
once at 95.9% idle, no other `xcodebuild` either time, 6.6 MiB both times. A footprint *difference*
between two readings seconds apart cancels the host noise that makes milliseconds untrustworthy here.

**Three corrections to the arithmetic built on that number, verified against the tree, and they do not
all point the same way.**

*The unit label was wrong and the slope understates the path that matters.* "787 MB" and "6.6 MiB"
are only mutually consistent at **6.558 MiB** (787 ÷ 120), and both are **MiB**, not MB — the test's
own `megabytes()` helper divides by `1_048_576` and prints the literal string `"MB"`. And 6.558 MiB is
the *stamping* path: `inkOneCel` (`PerfBaselineTests.swift:2800-2814`) draws three sine strokes that
touch roughly 82% of a cel's rows. **The *load* path has never been measured, and it touches every
row**: `RasterLayerTexture.setContents` (`RasterLayerTexture.swift:231-247`) runs `ctx.clear(full)`
then `image.draw(in: CGRect(origin: .zero, size: size))` over the whole canvas rect, so a cel arriving
from a package is the full **8.0 MiB (INFERRED, `w·h·4`, still never measured directly)** — the number
this item was sized on all along, not the smaller one this section reported.

*Item 13's 656 MiB, which this item was weighed against, double-counts headroom that is not gone.*
It is a sum of five *ceilings*, and four of the five cannot be reached at 2048×1024: the compositor's
real occupancy at six layers is 48 MiB against its 192 MiB ceiling (§2 item 1), the onion skin at its
shipped `previousCount = nextCount = 1` holds ~6 MiB against 64, and the mask cache is near 0 without
alpha masks in the frame. **A defensible steady state is ~250–450 MiB**, not 656 (INFERRED, and every
term in it is a ceiling nobody has observed full). Adding the full 656 to a cel-residency figure
overstates what is actually spoken for.

*The owner's real documents were read directly, and they are nothing like the size this item feared.*
An 11-agent scoping pass re-opened this item on the strength of the owner's stated intent (below);
before any of it was built, **the owner's own iPad container was read over `devicectl`.** Across all
25 project packages on the device — live, `Documents/Backups`, and `Documents/Trash` — **the largest
has 4 cels.** The two live projects (`Documents/Projects/Untitled.paintproj`, `Untitled 2.paintproj`)
have **1 cel each**. `Untitled.paintproj`'s own `manifest.json`, pulled off the device: 1 layer,
`'Vector 1'`, `kind=vector`, 1 cel, `startFrame 0`, `frameCount 12` — one drawing held across twelve
frames.

**What the owner actually asked for, and why that does not make the fear real today.** Asked directly
what a real document looks like, the owner's answer, in substance: **100–200 frames on 3–5 layers they
actually draw on — 300–1000 drawn cels.** Label this **OWNER-STATED**, and note plainly that it is an
**intention about the work they mean to do, not a count of cels in any package that exists** — the
device measurement above is what settles which of the two this item should be scoped against. The app
has never once been asked to hold more than 4 cels. This is a *forward* requirement, not a fire, and
item 15's "~3 s gallery-leave" inference of a ~150-cel document is refuted by the same read (§1, §2
item 3) — whatever caused that report, it was not cel count, and the report is moot now that the save
fan-out shipped and reads as instant.

**The expensive half — evicting the primary data, in any form — stays DECLINED, and the reason has
sharpened rather than weakened.** It was declined on 2026-08-20 because the harm to prevent was
unconfirmed; it stays declined now because three independently-scoped designs for the evict-and-
rehydrate contract flip — a frame-distance eviction window backed by the saved package, a sixth
byte-budget with write-back LRU on `CompositorBudget`'s own rule, and deferred ("never-decode")
materialisation — were each traced by adversarial review to a **silent-artwork-loss path in code that
already exists**, independent of whether the owner's future document ever gets built:
- The windowed design's `hasContent` door (`RasterLayerTexture.swift:188-192`) is consulted by
  `flipCanvas` and `setCanvasPadding`, both of which call `history.removeAll()` one line later and
  both of which would, under deferral, read every off-window cel as blank and silently discard it —
  a whole-document loss from one menu tap, invisible until the next autosave rotates the good package
  out of the backup slots.
- The write-back design keys eviction-safety by cel UUID while `applyCelChange`
  (`SelectionModels.swift:487-491`) rebinds cel→texture by version, so a displaced undo texture can
  stay marked "clean" while the file it is meant to be backed by has already been overwritten.
- None of the three is justified by a document that has never existed on this device; none passed its
  own adversarial review even against the document the owner says they intend.

**The cheap half SHIPPED 2026-08-22: a cel that carries no raster content no longer writes, loads or
allocates one.** It is correctness-clean — it removes data that was never used, not data anyone might
still want — it is the largest single term this item can affect for the document the owner intends,
and unlike the contract flip it needed nothing from the thumbnail-persistence precondition item 9(c)
left owed.

*What was actually there, read off the owner's own device 2026-08-22.*
`Documents/Projects/Untitled 2.paintproj` — 3 cels on 3 layers at **2048×2048**, two vector layers and
one raster layer — carried a `<uuid>_raster.png` of **exactly 73,558 bytes on every one of the three**,
and all three were **fully transparent (alpha min = max = 0), including the one on the raster layer**.
So the document paid three canvas-sized PNG encodes per save and three 2048·2048·4 = **16 MiB**
`CGContext`s per load for zero pixels.

*The mechanism, as it was.* `ProjectStore.writeCel` wrote `cel.rasterImage` for **every** cel
unconditionally; `cel.rasterImage` was `cel.raster.renderToUIImage()`, and
`RasterLayerTexture.renderToUIImage()` has a non-optional return — with no backing context it **mints**
a transparent canvas-sized image and **memoizes** it in `cachedImage`, which nothing ever drops. So
merely *taking a save snapshot* allocated 16 MiB per blank cel on the main actor and pinned it for the
session, before the encode this item was named after had even started.

*What shipped, in four parts.*
1. **Save.** `RasterLayerTexture.hasContent` is now internal and is the predicate; `SaveSnapshot.CelContent.rasterImage`
   is `UIImage?`. A blank tier never calls `renderToUIImage()`, so the 16 MiB is not minted at all —
   not merely not encoded. **The predicate is the bitmap existing, never a pixel scan and never a
   stroke count**: `context == nil` implies "no pixels" by construction, which is the direction that
   cannot lose artwork.
2. **Manifest.** One new key, `CelManifest.rasterOmitted: Bool?`. `rasterFileName` **stays
   non-optional** — its absence is what makes PencilKit-era manifests fail to decode, which is what
   has the gallery *skip* those projects rather than open them blank, and that is not this key's
   business to retire. An old build reading a new package ignores the unknown key, finds no file, and
   lands on `decodeCel`'s existing `?? .empty(size:)`.
3. **Validate.** `ProjectBackupManager.validateProject`'s skeleton learned the same key in the same
   commit, and it had to: it gates the atomic swap, so a validator still demanding the file would have
   moved every staged package to Trash *while the save reported success* — silent total loss of every
   edit in an app that looked fine. A package that **names** a raster and cannot produce it is still
   damaged; both directions are pinned by tests.
4. **Load, and the heal.** `rasterOmitted` goes straight to `.empty(size:)`. A **legacy** package still
   has the blank PNG on disk, so after loading one the alpha is scanned **exactly** — byte loop, early
   exit on the first non-zero alpha, no downsampling — and the bitmap released if nothing is there,
   with `strokeCount` back to 0. Without the heal a document that exists today would re-write its
   transparent PNG on every save forever. The 0 also finally lets `Cel.isCertainlyBlank` answer true
   for a reloaded blank cel, so the onion skin skips a canvas-sized draw it used to pay.

*The number.* `PerfBaselineTests.testWhatAVectorOnlyDocumentCostsToSaveAndLoad` — **60 vector-only
cels on 3 layers at the owner's real 2048×2048**, the shape of `Untitled 2.paintproj` scaled to where
the figures read against the noise. **MEASURED 2026-08-22 on the `rasteromit` simulator (iOS 26.5,
iPad Pro 13-inch M4, Debug), three samples each way, alternated against the same binary:**

| | before | after |
|---|---|---|
| package on disk | 6.9 MB | **4.6 MB** |
| of which `_raster.png` | 2.3 MB in **60 files** (34% of the package) | **0 bytes in 0 files** |
| PNGs encoded per save (`SaveProfile.pngsEncoded`) | 60 | **0** |
| save, awaited | 645 / 648 / 540 ms | **188 / 192 / 240 ms** |
| per cel | 10.7 / 10.8 / 9.0 ms | **3.1 / 3.2 / 4.0 ms** |
| `phys_footprint` after a load | 3317.1 / 3317.6 / 3319.5 MB | **1865.1 / 1865.3 / 1865.7 MB** |

**~1453 MB, or ~24.2 MB a cel**, and the footprint readings are steady to under 1 MB across three
samples each way — a memory *difference* in one process cancels the host noise that makes milliseconds
untrustworthy here (§6). 16 MiB of the 24.2 is the `CGContext` arithmetic exactly; the rest is the
decoded `UIImage` the load no longer holds beside it.

**Load wall-clock did not move, and saying so is the point.** Before: 4579 / 4720 / 5577 ms. After:
6183 / 6010 / 4939 ms — two overlapping ranges on a Mac that was at **5.2% idle** while the after arm
ran. This fixture's load is dominated by rasterizing 60 vector cels for their thumbnails, which this
change does not touch. **Read the bytes and the footprint, not the clock.**

*Where it does not help.* A cel whose texture holds an allocated-but-transparent bitmap — one erased
back to nothing, or handed a whole-canvas composite by `bakedRasterTexture` — still reports content
and is still written. That is deliberate: `context != nil` with transparent pixels is the conservative
direction, and the only cost of being wrong that way is one PNG.

**What is still unmeasured, so nothing above reads as more settled than it is:**
- **The real pre-jetsam ceiling on the iPad 9.** The ~1.4 GB figure this item has leaned on traces to
  the word *"perhaps"* in a doc comment (`Compositor.swift:102-103`, *"a device where the whole app
  has perhaps 1.4 GB before jetsam"*), hard-coded once as `1400 * mib` in
  `MemoryBudgetLogicTests.swift:103`. It has never been read off the device.
- **The residency slope on the load path** — see the first correction above; 6.558 MiB is stamping,
  not loading, and the two may not agree.
- **Whether iOS's memory compressor absorbs cold cel residency.** `phys_footprint` counts compressed
  pages at their *compressed* size, and a mostly-transparent RGBA cel is long runs of zeros — exactly
  what a compressor eats first. Every figure in this document was taken on a Mac under no memory
  pressure, where nothing was ever compressed. **This is the one term that can move the whole answer
  by a factor, not a percentage**, and it is untouched by anything in this item.

*Shipped from this item*: the instrument, item 9(a)'s pattern — measure, record, then decide — the
three corrections and the device read above, and, on 2026-08-22, the cheap half. The contract flip is
still not one of them, and the three unmeasured terms above are what would have to be settled before
it could be.

**16. The Move tool's live drag on a vector layer. — MEASURED and FIXED 2026-08-21.** Not from this
programme's ranking: the owner reported it off their own iPad, *"Move is extremely slow, reducing FPS
to 5fps"*, Release build, 2026-08-21.

**It is item 11's trap on the other per-input-event path, and it was worse.** `objectTransformChanged`
fired on every touch-move and did four canvas-sized things per sample:

1. `VectorCanvas.localContentBounds()` — a full rasterize of every element in the layer via
   `renderLocalContent()` (explicitly "not cached"), then `PixelOps.opaqueContentBounds`, a
   several-million-pixel alpha scan. To recompute the box's pivot and size.
2. `setVectorTransform` → `VectorCanvas.setTransform` → `invalidate()`, dropping the render memo.
3. `strokeView.refreshDisplay()` → `render()`, which missed the memo step 2 had just cleared and
   **rasterized every element a second time**,
4. then, because the transform is not the identity, blitted the result through it into a *second*
   canvas-sized context.

`updateTransformOverlay` asked for (1) again on any SwiftUI pass that happened to land mid-drag.

**The number.** `PerfBaselineTests.testWhatOneSampleOfAMoveDragCosts` drives 60 samples — one second
of touch-moves at 60 Hz — over a 12-stroke layer at the owner's **2048×1024**, with the two arms
**alternated inside one run** so the ratio cannot be an artefact of the machine drifting between them,
and a cold `render()` of a second untouched canvas as the **control**. MEASURED on `move-overlay-1`
(iOS 26.5 simulator, iPad Pro 13-inch M4, **Debug**, CoreGraphics — `VectorCanvas.render()` has no
Metal variant), two isolated runs with no other `xcodebuild` alive:

| per touch-move sample, 2048×1024 | run 1 (alone) | run 2 (alone) | run 3 (whole fast tier) |
|---|---|---|---|
| **before** — bounds, transform, render | **107.8 ms** | **96.1 ms** | **99.9 ms** |
| **after** — bounds (memo hit), transform, box layout | **~0.000 ms** | **0.002 ms** | **0.003 ms** |
| implied fps ceiling, before | 9 | 10 | 10 |
| *control*: cold `render()`, untouched code | 41.7 ms | 39.3 ms | 40.0 ms |

**Three readings, and the control spans 6% across all three** while the before arm spans 12% — which
is what says the ratio is about the code and not about the machine. Run 2 was taken at 66% idle with
this branch's own build still ramping and run 3 inside the whole fast tier rather than alone; neither
moved the answer. Recorded as three because this repo has been burned by single readings, and a
figure that survives three different loads is a different kind of claim from one that has not.

**A Debug simulator reading 9–10 fps against the owner's 5 fps in Release on an A13 agrees within a
factor of two**, which is not the 2–14% item 11's before-column managed against the device but is as
much as a *frame rate* has any right to claim: item 11 was comparing one term of a frame, and this is
a whole frame with the overlay, the thumbnail debounce and Core Animation in it. Item 11 explains why
even that much agreement should be expected — this path is entirely CPU-side, allocations and
stamping and a blit with no GPU in it, which is the condition §5's "the simulator misreports GPU cost
by more than 10×" does not cover — and the residual is an A13 against an M4, in the direction that
makes the device slower. **Do not read the factor of two as a device multiplier**; §1's ~1.3× still
governs compositing, and one coincidence is not a calibration.

**The finding worth carrying is not the number.** This path was found by an artist dragging
something, on the same build and the same afternoon that confirmed the fifteen-item programme on
hardware. The programme ranked by reading code and reasoning about canvas area, and an O(elements)
cost on a per-input-event path is invisible to both — exactly as item 10 says of the Mode 3 eraser,
and this is the second instance of that sentence being true.

**The fix is two halves, and the second is item 11's lesson rather than a new idea.**

*(a) The bounding box is memoized on content, not on the render.* `VectorCanvas` grows a
`contentVersion` that every mutation of `_elements` bumps and `setTransform` deliberately does not —
an overall transform moves the layer in canvas space and leaves it exactly where it was in its own
local space, so anything derived from local content survives it. `localContentBounds()` memoizes on
that. It costs one `CGRect?` to hold, so unlike the render memo it is invisible to `hasCachedImage`
and to eviction, which is correct rather than an oversight: there is nothing there to evict.
`ObjectTransformLogicTests.testTheLocalContentBoundsMemoSurvivesATransform` drives sixty samples of a
drag and asserts **one** rasterize, on a counter rather than on a millisecond.

*(b) The live drag rasterizes nothing.* Item 11's finding was that the fix is not a faster re-render
but no re-render, because Core Animation was compositing the result anyway — and a layer transform is
the most Core-Animation-friendly operation there is, since the pixels do not change at all, only
where they land. `StrokeCanvasView.beginLiveLayerTransform(base:)` latches the affine the displayed
image was rendered at and suppresses `refreshDisplay`; `updateLiveLayerTransform(_:)` assigns
`current · base⁻¹`, conjugated for `UIView.transform`'s centre anchor, to the image layer;
`endLiveLayerTransform()` clears both and rasterizes **once**. It is `TextTransformOverlayView`'s §4
rule 2 — "a 60 Hz corner drag rasterizes nothing" — arriving on the overlay ADD_TEXT.md was pointing
at.

*Risk, and how it was discharged.* The conjugation is the whole correctness of (b) and it is silently
right for a pure translation and wrong for every scale and rotation — the first draft had it
backwards. `testTheLiveViewTransformShowsWhatARerenderWouldHave` asserts the **mapping** over three
bases × four currents × five probe points, not the matrix, and it caught it. What is left unproven
headlessly is the *appearance* during the hold: the UI suite asserts where the layer lands after lift
(`VectorShapeAndRecoveryUITests.testContentDrawnOnAMovedVectorLayerLandsWhereItWasDrawn`), which
exercises the rasterize-on-lift path but not the frames before it.

*What this does not say.* It is not a frame rate on the owner's device, and it is not the whole
frame: a Move drag also runs `scheduleThumbnailRegen` (debounced) and `refreshUndoRedoState` (six
comparisons) per sample, both left alone. Whether Move now feels like Move on their iPad is open in
§6.
*Verified*: `testWhatOneSampleOfAMoveDragCosts` (`PerfBaselineTests`), and the memo's countable half
in `ObjectTransformLogicTests`.

---

**18. Where a canvas resize's time actually goes, and whether the vector arm is worth making cheap.
— MEASURED 2026-08-28. The optimisation is DECLINED; the measurement changes what stage 3 is for.**

The owner, on being told a resize takes 3–4 s at 300 cels and blocks the main thread:

> *"resize freezing canvas isnt that big of an issue, as long as the user knows its loading. It is a
> one time thing anyway. Although I wonder, why is it like that? since they are stored as signed
> ints, resizing (not asymetric cropping), shouldnt change the origin point and thus none of the
> stroke data."*

**Two premises in that, and they part company.** *On disk* it is right, and better than it claims:
TODO item (8) is a **save-time codec**, `PackedSampleRun` writes the quantisation origin into each
payload, and nothing on the resize path marks a stroke `precise` — `markedPrecise()`'s only caller
anywhere is the lasso move (`CanvasManager+LassoMove.swift:758`). So a resize forces no re-encode and
no decode, and it cannot change what an already-stored coordinate means — the next save writes
different bytes only because the geometry genuinely moved, never because the format's domain did.
*In memory* it is not right:
`VectorSample` is three `CGFloat` (`ShapeGeometry.swift:5-10`) and always has been — item (8) never
created a resident 16-bit form — so the display list a resize walks is doubles in canvas coordinates,
and a translation touches every one of them. **The stored-integer intuition is about the file; the
cost is in the tier above it.**

**MEASURED 2026-08-28**, `PerfBaselineTests.testWhereACanvasResizeSpendsItsTimeOnAVectorDocument`.
4 layers × 8 cels at 2048×1024 ↔ 1024×512, out and back, best of three by the whole figure, Debug,
simulator, **57.3% idle with no other `xcodebuild` running** — the quietest of three whole-test runs,
the other two at ~40% idle, and the shares moved by at most two points across all three. Every
absolute figure is a ceiling; the *shares* are the transferable half, because both arms are measured
on the same cels in the same run. Each cel carries the owner's measured density — **190 strokes**
(TODO.md, the cel read off their device) × 46 samples.

| document | mode | whole | vector arm | raster arm | remainder |
|---|---|---|---|---|---|
| **blank raster tiers** — what the owner's packages actually are | crop/expand | 56.0 ms — **0.9 ms/cel** | **54.5 ms — 97%** | 0.1 ms — 0% | 1.4 ms — 3% |
| | scale-to-fit | 56.4 ms — **0.9 ms/cel** | 54.1 ms — **96%** | 0.1 ms — 0% | 2.2 ms — 4% |
| **inked raster tiers** | crop/expand | 280.2 ms — 4.4 ms/cel | 54.3 ms — **19%** | 231.3 ms — **83%** | ~0 |
| | scale-to-fit | 562.2 ms — 8.8 ms/cel | 53.8 ms — **10%** | 524.4 ms — **93%** | ~0 |

*(The arms are timed separately from `whole`, so the three columns bracket it rather than summing to
it exactly; a share slightly over 100% on a noisier run is that, not a bookkeeping error.
`remainder` — the per-cel `autoreleasepool`, `commitAllInteractiveState()`, the guide walk,
`history.removeAll()`, nil'ing thumbnails, starting the backfill — is **0–4%** in every row.
`ProjectStore` and the manifest are not a term at all: nothing is written to disk during a resize,
and the test asserts that against an empty backup root rather than assuming it.)*

**Finding 1 — the 3–4 s figure is a raster figure, and the owner's documents are not that shape.**
Both existing resize measurements (`testWhatTheCanvasPaddingResizeCosts`,
`testWhatScalingEveryCelCostsAgainstCroppingIt`) run on `multiCelDocument`, which is **raster-only**:
its cels carry no `VectorCanvas` at all, so the vector arm's share of those numbers is not "small",
it is *zero*. Item 14 read the owner's iPad directly on 2026-08-22 and found every raster tier fully
transparent — and the heal that shipped that day turns such a tier into `.empty(size:)`, which
`RasterLayerTexture.resized(to:placing:)` early-outs on. **On a real document the raster arm costs
nothing and the whole resize is 0.9 ms/cel: 0.27 s at 300 cels and 0.89 s at 1000** (INFERRED,
linear in cel count by construction), in Debug, against 3.0–4.0 s and 9.9–13.3 s for the raster
fixture. A resize of the owner's own artwork is a *tenth* of what CANVAS_RESIZE.md §2 has been
planning against, and the difference is entirely whether the raster tiers hold pixels.

*The limit of that claim.* Item 14 read the `raster` tier; `fillImage` and `bakedImage` are separate
tiers with separate files and no `hasContent` door of their own — only the cel's `if let` skips them.
A document where the bucket fill or a select-and-move has been used carries one or two more
canvas-sized redraws a cel and sits between the two rows above. The blank row is a floor for a real
document, not a promise about every one.

**Finding 2 — inside the vector arm, the arithmetic is not the hot part.** Three probes in the same
test, over the same 64 cel-resizes:

| | crop/expand, blank raster |
|---|---|
| `vectorFloor` — `resized`'s own identity early-out: lock, one `VectorCanvas`, the element array retained rather than rebuilt | **0.1 ms** |
| `vectorChurn` — every allocation and retain the real walk makes, with `point.applying(t)` replaced by a copy of the same three numbers | **46.0 ms (84%)** |
| `vectorMaths` — the residual, i.e. the similarity itself | **8.3 ms (15%)** |

Twelve rows across the three runs gave 7.3–10.8 ms of maths against 45.7–59.0 ms of churn — with one
noisy row landing at 0.0, because the residual between two ~55 ms figures is inside the noise on a
loaded machine, which is exactly why the quiet run is the one quoted. Read it as **~15% maths, ~84%
allocation, and a per-cel floor of essentially zero**. `drawn`'s
`stroke.samples = stroke.samples.map { … }` mints a fresh `[VectorSample]` per stroke — 190 array
allocations a cel — and that, not the four multiplies and four adds per point, is what a resize
spends its vector time on.

**Ranked, and declined.** The prize for making crop/expand's vector translate free is 100% of a
resize on a real document and 19% on a raster-heavy one — but 100% of 0.27 s at 300 cels, in Debug,
on an operation the owner has just ruled may block as long as it says it is loading (TODO item (9),
CANVAS_RESIZE.md §5 rule 15). It is not worth a correctness risk and it is not worth a revert; see
§5's entry, which is where the tempting version of it is ruled out. **If it is ever wanted, the lever
is the allocation and not the geometry**: taking ownership of the element array and mutating samples
in place, rather than `map`-ing a new one, is a local change inside `drawn(_:through:widthScale:)`
with no bearing on where any dab lands. It needs care about who else still holds the old
`VectorCanvas` (undo closures, the interpolation render cache), which is why it is a note here rather
than a scheduled item.

*Verified*: `PerfBaselineTests.testWhereACanvasResizeSpendsItsTimeOnAVectorDocument`.

*One figure this item could not launder.* [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) §9.6 asks for the
**8,714 samples** on the owner's own cel to be landed here labelled MEASURED with its provenance. It
still has none — it is not traceable to any run in this repo, and this pass did not find one. What is
recorded instead is the *190 strokes* beside it, which TODO.md does carry, and a fixture built as
190 × 46 = 8,740, which reproduces the shape to within a third of a percent without claiming the
original number's authority. Somebody with the device can settle it in a minute; nobody should quote
8,714 as MEASURED until they do.

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

**Do not re-introduce a translation-only `VectorCanvas._transform` to make crop/expand cheap.** It is
the natural reading of the owner's *"resizing … shouldnt change the origin point and thus none of the
stroke data"*, it is what `resized(to:offset:)` did until TODO item (12) stage 3, and item 18 above
prices what it would buy: 100% of a 0.27 s operation at 300 cels on a real document, in Debug, on a
path the owner has ruled may block. **It does not even buy that**, and that is the part worth keeping:
`VectorCanvasData.init(from:canvas:)` bakes any carried transform through
`VectorCanvas.mapping` on **encode** and writes `transform = []` (`VectorLayer.swift:3426-3444`), so
the walk is not removed, it is *moved to the next save* — off a path the artist was told is loading
and onto one item 15 fought for milliseconds on, with the save's cost now silently depending on
whether a resize happened. [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) §10 carries which of that
document's three defects come back with it (A and C do; B cannot) and the two further costs — the
item (8) encoder quantises about the *canvas* centre, and `bakePreciseStrokes` snaps onto that same
grid, both of which are wrong by `d` the moment stored geometry stops being canvas geometry.

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

**Do not build a dirty-tracking save — settled for good, 2026-08-21.** *(Both preconditions this entry
named are now met — item 1 landed 2026-08-18 and item 9's instrumentation landed 2026-08-20 — so what
follows was the whole of the argument rather than a wait. **Item 15 then measured this path and took
the safe 4× off it without touching what gets written**, which lowered the pressure on this entry
rather than raising it: the encode is now spread over cores, so the memo below was worth a further
~3.7 ms a cel on the cels that did not change, not the whole 15. **The question §6 asked before
building anything further here came back "instant"** — the owner, Release build `38e22c6`, iPad 9:
*"leaving the gallery is instant."* The memo stays unbuilt for good.)*
Skipping unchanged PNGs is the right eventual answer to the gallery-exit wait, but it is the
data-loss class of risk: a dirty check that is wrong once silently drops artwork, which is worse than
any stall — and this repo already carries `ProjectBackupManager` and `validateProject` precisely
because that failure mode is unacceptable. Item 1 removes two thirds of the cost for one line and zero
correctness exposure. A cheaper intermediate exists: memoize `pngData()` alongside the existing
version-keyed `renderToUIImage()` cache, which gets most of the win without changing *what* gets
written. If the full version is ever built, it must fail closed — re-encode when unsure.

---

## 6. Open questions

Several of these were put to the owner, on 2026-08-18 and again on 2026-08-21 once a Release build
of `38e22c6` was on their iPad 9, and are answered below. The rest are open, and each is recorded
with the measurement that would close it rather than as a topic.

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
so §1's "scales with cel count, not with area" is confirmed rather than assumed. The owner's "~3 s"
was inferred at the time to be a ~150-cel document, which the device read of the owner's actual
projects (item 14) has since refuted — 1–4 cels each, not ~150. It is now 117.1 ms for a 32-cel
document, and **the owner reports leaving the gallery instant on the device** (below).
**The surprise was the ratio, not the total**: the entire ranking of this path had assumed the file
write mattered, and it is 2%.

**Does their 4096² document still draw at 17 fps? — ANSWERED 2026-08-21: no.** Item 11 deleted ~43 ms
of per-dab CPU work at that size on the simulator; the owner's own words on a Release build of
`38e22c6` on their iPad 9: *"17fps is gone, good job. 4k screen displays full 60fps when painting."*
This closes the live question item 8/11 left open — the ceiling now sits above the display's 60 Hz —
and it is the headline result of the whole performance programme.

**Does leaving to the gallery still feel like ~3 s? — ANSWERED 2026-08-21: no, it is instant.** Item
15 measured the wait for the first time and made it 4× shorter on the simulator; the owner's own
words on the same Release build: *"leaving the gallery is instant."* **§5's dirty-tracking memo stays
unbuilt for good** — the handoff that carried this question said exactly that would follow if the
answer came back this way.

**Is opening a project any better, and does the timeline's cel-blocks-arriving-blank behaviour read
as loading rather than broken? — ANSWERED 2026-08-21: "no issues."** Item 9(c)'s deliberate behaviour
change is accepted as designed.

**The lasso, on the two named device scenes (a shape with a gap in its outline, and a loop drawn well
outside the shape) — ANSWERED 2026-08-21: "lasso fill works."** All seven of the device checks run
this pass now have an answer, and all four of the owner's originally reported bugs are confirmed
fixed on hardware rather than only headlessly. This is the named lasso check only — it does not touch
[BUGS.md](BUGS.md)'s separate, more specific same-layer paint-over entries, which were not part of
what was run.

**How many drawn cels does a real document of the owner's actually carry? — ANSWERED 2026-08-21, and
the answer has two parts that do not agree.** OWNER-STATED intent: 100–200 frames on 3–5 drawn layers,
300–1000 drawn cels — a description of the work they mean to do. MEASURED, direct read of the iPad
container over `devicectl`: the largest of all 25 packages on the device (live, `Backups`, `Trash`)
has **4 cels**; the two live projects have **1 cel each**. The app has never been asked to hold more
than 4. See item 14's rewrite for what this changes and does not change — the forward intent keeps the
question open for design purposes even though the immediate alarm it raised does not describe anything
that exists yet.

**How much does a machine under load change a figure here? — ANSWERED, and it is worse than "slower".**
The same test, same binary, same day: `saveForReference` read 863 ms on an idle Mac, 988 ms with two
other suites running, and 3187 ms with three. The decode's cold-versus-warm gap read 1.4× idle and
~2.2× contended. A number taken under contention is not a number with a wider error bar; it is a
number about a different thing. `pgrep -fl xcodebuild` and `top -l 2 -n 0 -s 2` before, and state
what they said.

### Still open

**Does a Move drag on the owner's iPad now run at frame rate?** Item 16 took the per-sample model
cost from 96–108 ms to 0.002 ms at their canvas, but every one of those figures is a Debug simulator
and their 5 fps was a Release build on an A13. The shape transfers; the multiplier does not.
*The measurement*: they drag a vector layer with the Move tool on a real document and say — and, for
a figure rather than an impression, a Release build of `main` on that iPad. **The same run answers
the handle question**: whether the grips are now findable with a fingertip at the zoom they actually
work at is a thing only a finger can report.

**Does Core Animation actually pay for the non-native pixel format, and where?** Whether the mismatch
is a background IOSurface conversion, a lazy decode at commit-prepare on the calling thread, or
nothing meaningful is not answerable by reading code. *The measurement*: one Instruments Core
Animation "Color Copied Images" pass on the device. Until it comes back, see §5.

**Does undo history ever approach its cap in real use in a session? — still technically open, but the
owner has ruled on the sizing directly rather than waiting for the sample.** `UndoHistory.currentCost`
exists precisely so this can be sampled, and nobody has yet. **The two questions the sample would have
answered are answered anyway, 2026-08-21, OWNER-STATED**: 192 MiB (~12 whole-cel operations) is the
right budget, and trimming to half (~6) on a memory warning is the right response. Both are decisions
now, not guesses wearing constants' clothes — see item 13. What is left open is only the empirical
question of whether a real session ever gets near either number, which no longer gates anything.

**Is an in-between frame's 1.86× still acceptable on the device, in Release?** §7 measured the cost
of engaging the compositor on in-betweens at the owner's canvas and shipped it, on the argument that
the extra frames join a bill the document was already paying. Every figure there is a Debug
simulator. *The measurement*: the owner scrubs across a span of in-betweens on a document with a
blend mode or an adjustment layer, in a Release build on their iPad, and says whether it tracks.
The same run also settles whether §7's double evaluation is worth closing.

**What is the real cache occupancy at background time?** Item 12's ~384 MiB is a budget ceiling, not
an observation. *The measurement*: sample `residentBytes()` and the upload-cache counters immediately
before backgrounding, on the device.

**Is one save on the way out still a felt pause?** Tier A cut the app switch from three full saves to
one, and made that one composite a 320×160 tile instead of the whole canvas. Whether the freeze the
owner reported is *gone* or merely *smaller* is not answerable from here, and it was not one of the
seven checks run on the device 2026-08-21. *The measurement*: the owner switching away from a real
document on their iPad and saying.

**Item 14's three still-unmeasured terms, carried from its 2026-08-21 rewrite.** The real pre-jetsam
ceiling on the iPad 9 — the ~1.4 GB figure traces to the word "perhaps" in a `Compositor.swift` doc
comment, hard-coded once in `MemoryBudgetLogicTests`, and has never been read off the device. The
residency slope on the *load* path, as opposed to the *stamping* path item 14 actually measured.
And whether iOS's memory compressor absorbs cold cel residency — a mostly-transparent RGBA cel is
long runs of zeros, every figure in this document was taken where nothing was ever compressed, and
this is the one term that could move the answer by a factor rather than a percentage.


---

## 7. What engaging the compositor on an in-between costs (2026-08-29)

Until this date `isSandwichEngaged` refused whenever any layer's active cel carried an interpolation
recipe, so the artist's blend modes, effects and §6.4 mask clipping were silently off on every
in-between frame (KEYFRAMES.md §10). `renderSources` hands every flatten its `DerivedCelContent` as
of `531cb0a`, so the composite contains in-betweens and the refusal has nothing left to protect —
but taking it out means the live canvas now composites on frames it used to skip, **and every one of
those frames also evaluates a derivation**. This is that cost, measured before shipping the removal.

**MEASURED 2026-08-29**, `PerfBaselineTests.testWhatEngagingTheCompositorOnAnInBetweenCosts`, iPad
Pro 13-inch (M4) **simulator**, Debug, `Compositor.backend == .automatic`, canvas **2048×1024** (§1 —
the owner's, not this file's default 2048²), three layers with one `.multiply`, a cold forward scrub
across six distinct in-between cels, `rasterizeCache` cleared before each arm. Machine at 61% idle
with no other `xcodebuild` running (§6's contention rule). Three consecutive runs, median quoted;
spread across the three was under 4% on every figure.

| per frame of the scrub | ms | what it is |
|---|---|---|
| in-between frame, **before** | **24.5** | one ARAP evaluation for the layer host. The compositor was refused, so this was all of it |
| ordinary frame of the same document | 53.8 | the sandwich as it already runs today — snapshot plus three composites, no derivation |
| in-between frame, sandwich only | 74.2 | …plus the composite's own evaluation of the in-between (+20.4) |
| in-between frame, **after** | **100.2** | …plus the layer host's evaluation of the *same* in-between, a second time (+26.0) |

**The change costs +75.7 ms per in-between frame, and makes an in-between frame 1.86× an ordinary
frame of the same document.** That is the number the decision rests on, and the framing that matters
is the middle row: this is not a new class of cost appearing on a cheap document, it is frames
joining a bill the document was already paying everywhere else. A document with no blend, effect,
mask or node never engages at all and is untouched (`needsCompositorOnCanvas`, still the first
clause). Simulator Debug figures — the device runs ~1.3× the simulator (§1) but Release is a
different order on this path, so treat the **ratio** as the transferable part and none of the
absolutes as device numbers.

**The `t` slider is the one interaction this could not absorb, and it gets a clause instead of a
budget.** `setInterpolationT` writes `recipe.t` on every tick of the drag, and the derivation is in
`SandwichKey` now, so every tick would be a fresh 100 ms. `sandwichEngagesOnCanvas` disengages while
`isScrubbingInterpolation` — a **gesture** clause, like the two it sits beside (a floating Move piece,
a lasso move's latched piece), rather than the frame clause it replaced. The artist loses the blend
on the drag and has it back on commit; the drag is the one moment they are looking at the in-between
rather than at the picture around it.

### Found and not fixed: the in-between is evaluated twice per frame

The fourth row costs 26.0 ms more than the third for one reason: `updateInterpolationPreviews`
renders the derivation for the layer host, and `PixelOps.rasterize` renders **the same derivation
again** for the snapshot. Two memos, two entry points, one ARAP solve done twice — worth ~26% of the
after-cost. Neither memo is wrong; they are keyed on different things (`InterpolationPreviewKey` on
the identity, `RasterizeKey` on cel-plus-identity-plus-quality) and neither can serve the other's
question as it stands.

Two ways out, neither taken here. **(a)** Skip the host render while the sandwich has the host
blanked — cheap, but it couples `updateInterpolationPreviews` to sandwich state and has to survive
the window `updateSandwich` calls "trap 1", where the hosts are deliberately *not* yet blanked.
**(b)** Memoize `DerivedCelContent.render` itself, which is where both callers meet — structurally
the better answer, and a new canvas-sized image cache with its own memory story, which
`CelContentProvider` deliberately left out ("called only on a memo miss, which is why it is a thunk").
KEYFRAMES §4.6's span-scoped disk-backed cache is the same machinery asked for by a different
feature, so this probably wants doing there rather than twice.

### The per-pass term, which is small

`makeSandwichKey` now resolves a derivation for every layer on every SwiftUI pass, and `SandwichKey`'s
`!=` compares the identities it built — including each motion group's fitted lattices, which are
vertex arrays sized by the drawing rather than by the canvas. Build plus equal-comparison, which is
what a pass on which nothing changed costs: **0.046 ms** (MEASURED, same run, `keyPerSwiftUIPass`).
Recorded rather than optimised; it is two orders below the rebuild it gates.
