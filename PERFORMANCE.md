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
against a device-derived budget of **183.7 MB** (MEASURED on the owner's iPad 9, §9;
`Compositor.swift:167-170`, `physicalMemory / 16` — 192 MiB is the `3 << 30 / 16` arithmetic rather
than the number the device produces), so nothing at this canvas is ever cut into strips or chunks. The
384 MiB crash table at `Compositor.swift:91-97` is 4096² arithmetic. Do not tune these constants.

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
| Compositor fixed per-call overhead | A fixed term, paid twice per sandwich rebuild — the two mid-stroke halves; the rest picture is read from the bake | `RenderTree.swift:429-431`, paid in `CanvasView.startSandwichRebuild` |
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

**And it applies to *compositing*, which is narrower than "every simulator number" makes it sound.**
§10.2 measured the bake store's codec both ways on 2026-09-02 and the device came out **2.5–4.9× faster**,
not 1.3× slower — a Debug simulator against a Release device is a different comparison from the paired
one above, and on that path the two halves of the cost did not merely scale, they **swapped places**.
Before extrapolating this factor onto anything that is not a composite, read §10.2's last subsection:
it is the case where the ratio was not the problem and the *split* was.

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
cores, so it is no longer the tick's headline; the composites, MEASURED at 22.4 ms for the three a
rebuild then ran and off the main thread, are the same size as it. A rebuild is **two** composites now
— the rest picture is read from the bake (RENDER §3.6) — so 22.4 ms is the ceiling rather than the
figure. Nothing on this tick is unmeasured any more, and none of it is the timeline's.

**5. Playback stuttering on documents with a mask, blend mode, or grade.** `startSandwichRebuild`
still computes `below` and `above` unconditionally even though they are shown only while `midStroke`
is true — item 4b explains why that was measured and left alone. The third composite is gone outright:
the rest picture is read from the bake (RENDER §3.6), which is also what playback now plays. Every
playback tick, scrub tick and undo still computes the two halves nobody sees. It runs off-main on
`sandwichQueue`, so it burns cores rather than freezing the UI — but `isSandwichRebuilding` serialises,
so a rebuild slower than the frame interval drops frames. A six-layer sandwich rebuild at 2048² costs
**54.8 ms warm on Metal, 64.7 ms on CoreGraphics** (MEASURED, iPad 9, Release, `Compositor.swift:36`)
against a 41.6 ms budget at 24 fps. **That figure is a rebuild of three composites and a rebuild is
two now, so it is an upper bound rather than the number** — and nobody has re-measured it. Do not
divide it by anything: `below` and `above` together do roughly the work `full` did on its own, so what
came off is not a third of the total. Only fires where `needsCompositorOnCanvas` is true; a
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

**4a. Cache `full` across a pure `activeLayerIndex` change. — SHIPPED, then SUPERSEDED by the baker.**
The live canvas does not composite `full` at all now: the rest picture is read out of the on-disk bake
(RENDER.md §3.6, stage 4d), whose key has no field for the active leaf, so a layer tap is a ring or
store hit rather than a composite a second key had to be kept in order to skip. `SandwichFullKey` and
the reuse path it keyed are deleted, and a rebuild is the two halves and nothing else
(`testARebuildIsTheTwoHalvesAndNothingElse`).
*The claim underneath it still holds*: `activeLayerIndex` is read in exactly one place, the
`split(atLeaf:)` that makes `below` and `above`, and `full` is the whole tree, uncut — pinned by
`testFullIsTheSamePictureWhicheverLayerIsActive`, pixel-identical over every index on a document with
a blend in it.
*What the cache measured while it existed*: `CompositeProbe` (in `Compositor.swift`, and now the
instrument the chunk and bake suites count with) records every composite and its size, and the layer
switch came out at **2 composites where there were 3**, all the same size. That saving was on a path
that is gone; the equivalent count today is the 2 above.

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

**5. Give `makeRenderRequest` a render-size hint. — SHIPPED** (`RenderSizing.fitting`, and
`RenderRequest.renderSize(fitting:within:)`). Applied at one call site, the thumbnail composite in
`ProjectStore.SaveSnapshot`; `.native` everywhere else, which is byte-for-byte as before.
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
may only ask for less), and bounded below that by nothing: a box too large for the device's texture
budget is `StripedCompositor`'s problem, exactly as a native composite is (RENDER.md §3.8).
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

**Every figure above is the simulator, and on the owner's actual iPad the flatten fan-out is worth
1.41×, not ~3.9×.** MEASURED 2026-09-02, iPad 9th generation, Release, iOS 26.5.2, from a device run
of `PerfBaselineTests`: `testTheSnapshotFanOutIsSpreadOverCoresRatherThanWalkedSerially` reports
**serial 22.0 ms against parallel 15.6 ms over 6 cels at 2048×1024**, with
`activeProcessorCount = 6`. The A13 is two performance cores and four efficiency ones, so the count
is not the speedup — the 3.89×/3.92× above are what a simulator's six equal host cores give, and
nothing on the device reproduces them. **Do not quote the ~3.5× reading anywhere as a device
figure.**

The reading is not that the fan-out was a mistake — 6.4 ms a tick is real and it cost one primitive —
but that it never removed the term, and RENDER.md stage 2 does: the whole flatten now resolves on
`CanvasView.sandwichQueue`. `renderSources` no longer exists as one function; its two passes are
`CanvasManager.leafSnapshots` (main actor, O(layers), no pixel) and `FrameRecipe.resolveSources`
(the fan-out, on whatever queue resolved the recipe). **The device number that sizes stage 2 is the
snapshot itself: `snapshotCold` 36.3 ms against a 41.6 ms frame budget**, 87% of a frame on the main
thread at pen-up, plus a 70.3 ms committed re-render in front of it.

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
here: `renderToUIImage` off the scratch, **0.033 ms** per refresh, and the scratch's copy of the
render at touch-down — MEASURED at **7.7–11.2 ms once per gesture** while that copy was the whole
canvas, and a crop of the stroke's own window since `StrokeScratch`, so it scales with the stroke
rather than with the document.

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
ink but an eraser that shows nothing until lift. Neither gained an operation here — both took an
identity-guarded `showScratch(nil)`, a pointer comparison. (`.replacement` shows its punched window
through the scratch layer since `StrokeScratch`, over a base with that rect masked out; `.none` still
takes the pointer comparison.) Three things pin it: `VectorPreviewPlan`
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
`RasterLayerTexture.renderToUIImage()` has a non-optional return — with no backing context it then
**minted** a transparent canvas-sized image and **memoized** it in `cachedImage`, which nothing
dropped. (That half is fixed at the source as of 2026-09-01: a tier with no bitmap answers with a
shared 1×1 and memoizes nothing.) So
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
a sample's coordinates are resident as `CGFloat` (`StrokeSamples.positions`) — item (8) never created
a resident 16-bit form — so the display list a resize walks is doubles in canvas coordinates, and a
translation touches every one of them. (This line read *"`VectorSample` is three `CGFloat`
(`ShapeGeometry.swift:5-10`) and always has been"* until BRUSH.md §12 stage 4 made the record a channel
set; the coordinates are still doubles in memory, which is the part the argument rests on.) **The stored-integer intuition is about the file; the
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

**Do not tune `CompositorBudget` or `textureBudgetBytes`.** At 2048×1024 six canvas-sized textures are
48 MiB against a 183.7 MB budget. The admission valve never fires, and the strip planner that spends
the same number answers "one strip" — the unstripped path verbatim, no window, no apron, no crop.
Every number that forced any of it into existence is 4096² arithmetic.

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

**~~Is an in-between frame's 1.86× acceptable?~~ Answered 2026-08-29, OWNER-STATED — and what is
left open is a different question about a different thing.** The owner accepted the cost on seeing
§7's A/B, for the reason §7 records: the 24 fps budget belongs to the prebake (TODO (29)), not to
the live path. So "is the live frame fast enough" is **not** open and should not be re-litigated.

What is open is **whether the prebake, once it exists, plays at 24 fps** — which is a measurement
about §5b's design and not about §7's number, and cannot be taken until something bakes. Until then
the only live-path figure worth having is a *device* one: every number in §7 is a Debug simulator,
and the owner scrubbing a span of in-betweens over a blend mode in a Release build on their iPad
would say whether the live path feels right in the meantime. That is worth an hour of theirs, not a
week of ours.

**And a re-take of §7's four rows in Release on that device is a real open measurement, not a
formality** — §7 explains why the Debug quotient is a ceiling rather than a constant (its rows mix
Swift and framework work in different proportions, and only the Swift half carries the Debug
penalty). 1.86× is the worst case; nobody knows the real one, and nobody should design against the
Debug figure.

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
| ordinary frame of the same document | 53.8 | the sandwich as it ran when this was taken — snapshot plus three composites, no derivation. A rebuild is two composites now (RENDER §3.6), so this row is an upper bound |
| in-between frame, sandwich only | 74.2 | …plus the composite's own evaluation of the in-between (+20.4) |
| in-between frame, **after** | **100.2** | …plus the layer host's evaluation of the *same* in-between, a second time (+26.0) |

**The change costs +75.7 ms per in-between frame, and makes an in-between frame 1.86× an ordinary
frame of the same document.** That is the number the decision rests on, and the framing that matters
is the middle row: this is not a new class of cost appearing on a cheap document, it is frames
joining a bill the document was already paying everywhere else. A document with no blend, effect,
mask or node never engages at all and is untouched (`needsCompositorOnCanvas`, still the first
clause).

**Neither the absolutes nor the ratio are device figures, and an earlier version of this paragraph
said the ratio was — that was wrong.** It told the reader to treat 1.86× as the transferable part on
the grounds that a quotient cancels the Debug penalty. It does not, because the penalty is not one
number applied to one thing. Each row is a sum of two halves that shrink by very different factors
in Release:

- a **Swift** half — the ARAP polar interpolation, the lattice warp, `BrushStamper`'s dab walk. This
  is the kind of path CLAUDE.md's *"Debug measured 62x slower than Release"* note is about: tight
  scalar loops with bounds-checking and no inlining in Debug.
- a **CoreGraphics/Metal** half — the composites, which are already-optimised framework and driver
  code and barely notice the configuration.

The rows are not the same mixture of the two. The `before` row is *almost entirely* the Swift half
(one ARAP evaluation, no composite); the `ordinary frame` row is *almost entirely* the framework
half (three composites, no evaluation). So Release shrinks the numerator and the denominator by
different factors and **the quotient moves with them** — and it moves in this change's favour, since
the arms that shrink most are the evaluation ones the change adds. **Treat 1.86× as a ceiling
measured under the configuration least kind to it, not as a constant.**

**All four rows want re-taking in Release on the owner's iPad before anyone designs against them**,
and until they are, the honest use of this table is the *ordering* of the rows and the fact that the
middle row exists — not any figure in it. §1's ~1.3× device-vs-simulator correction does not rescue
this either: that ratio was measured for compositing workloads, which is exactly the half of the
mixture that does *not* dominate the rows this change is about.

### The ruling, and the reason — OWNER-STATED 2026-08-29

**This cost was put to the owner with the A/B pictures beside it, and they accepted it.** Their
words:

> *"if we are planning for this feature, then it is okay for things to take more than 1/24th of a
> second, including in-betweens. Of course if a smarter faster way is possible which doesnt require a
> lot of code, then sure. It's a minor worry though since if it prebakes and can play at 24fps after,
> then the original ask is covered."*

**Read the reason, not just the verdict, because the verdict alone looks like negligence.** A future
reader who finds a 100 ms frame on the live canvas and does not know why it was allowed will either
"fix" it at the cost of the artist's blend modes — which is the behaviour this section exists to
record removing — or conclude the app is broken. It is neither. The ruling is:

**The 24 fps budget belongs to the prebake, not to the live path.** "The feature" the owner names is
**background baking for playback** ([TODO.md](TODO.md) item (29), asked and recorded the same day):
the animation bakes in the background, non-current frames are gradually replaced by that baked
"video", and playback plays frames rather than compositing them. **It exists** — RENDER.md §3.5-3.7,
stages 4 and 5 merged: the canvas at rest and playback are served from LZ4 frames on disk through a
decoded ring, and only the two mid-stroke halves are still composited live. So what has to hit 41 ms is the **playback of a baked frame**, and the live composite of the frame
the artist is *looking at while drawing* is a different budget with a different consumer: one person,
one frame, at the pace of an edit. [KEYFRAMES.md](KEYFRAMES.md) §2.25 states this as a ruling in its
own right — *the live per-frame cost of a derived frame is not held to the 24 fps budget; the prebake
is what must play at 24 fps* — and that is the sentence to read before optimising anything on this
path.

So this section is **not** an open performance problem awaiting a fix. It is a recorded, accepted,
reasoned cost. The thing that would make it a problem again is the prebake *still* not playing at
24 fps — a measurement about §5b and not about this number, and **one nobody has taken on the device
now that the prebake is merged.** §10's decode figures say a frame reaches the screen in 1.5 ms at the
owner's canvas and 24.6 ms at 4096²; what is unmeasured is whether the baker keeps up with a scrub.

**One door is explicitly open** — *"if a smarter faster way is possible which doesnt require a lot of
code, then sure"* — and the next subsection is exactly that door. It is a cheap win, not an
outstanding tax.

**The `t` slider is the one interaction this could not absorb, and it gets a clause instead of a
budget.** `setInterpolationT` writes `recipe.t` on every tick of the drag, and the derivation is in
`SandwichKey` now, so every tick would be a fresh 100 ms. `sandwichEngagesOnCanvas` disengages while
`isScrubbingInterpolation` — a **gesture** clause, like the two it sits beside (a floating Move piece,
a lasso move's latched piece), rather than the frame clause it replaced. The artist loses the blend
on the drag and has it back on commit; the drag is the one moment they are looking at the in-between
rather than at the picture around it.

### The cheap win the owner left the door open for: the in-between is evaluated twice per frame

**This is the "smarter faster way that doesn't require a lot of code" the ruling above invites**, and
it is worth taking on its own merits rather than because the frame is slow — one ARAP solve done
twice is wrong whatever the budget says.

**Stated at its sharpest: with the compositor engaged, 26.0 ms of the 100.2 ms renders an image
nobody ever sees.** The layer host's evaluation happens, produces a canvas-sized in-between, and is
then *blanked* — `updateSandwich` masks every host at rest precisely because `full` already contains
that layer, so the pixels the host just spent an ARAP solve on are covered by the composite in the
same pass. It is not "the work is done twice and one copy is redundant"; it is that one of the two is
**discarded by design, every time, on every engaged in-between frame**. That is a quarter of the
frame's cost going to a bitmap with no viewer, and it is why this is worth doing rather than merely
tidy.

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

**And TODO (29) is now a third claimant on the same machine**, which settles it: that item's whole point
is that background baking is *already specified twice* (LAYER_COMPOSITING §9.2 for the shot,
KEYFRAMES §4.6 for the span) and that building them separately would give the app two frame caches
and two eviction policies. A memo on `DerivedCelContent.render` would be a third. **So (a) is the
right move if this is taken alone** — it is small, local, and buys ~26 ms of the ~76; **(b) belongs
to whoever unifies §5b**, and doing it here first would be the exact mistake §5b was written to
prevent.

### The per-pass term, which is small

`makeSandwichKey` now resolves a derivation for every layer on every SwiftUI pass, and `SandwichKey`'s
`!=` compares the identities it built — including each motion group's fitted lattices, which are
vertex arrays sized by the drawing rather than by the canvas. Build plus equal-comparison, which is
what a pass on which nothing changed costs: **0.046 ms** (MEASURED, same run, `keyPerSwiftUIPass`).
Recorded rather than optimised; it is two orders below the rebuild it gates.

---

## 8. Playback at 24 fps — the ranked list, written down and not yet investigated (2026-08-29)

The owner's goal, stated while ruling §2.25: *"Basically I want the app to be able to play in realtime
even with in betweens... if a smarter faster way is possible which doesnt require a lot of code, then
sure."* This is that list. **Nothing here has been measured for this item** — each entry names what is
already MEASURED elsewhere in this file and what would have to be established. Written so the next
session starts from a shortlist instead of a survey.

**Read this first, because it reframes the whole item.** *Composited playback already misses 24 fps
without any interpolation in the document* — §2 item 5, recorded 2026-08-20: a six-layer sandwich rebuild
at 2048² is **54.8 ms Metal / 64.7 ms CoreGraphics against a 41.6 ms budget** on the owner's iPad 9 in
**Release**, and `isSandwichRebuilding` serialises, so a rebuild slower than the frame interval drops
frames. In-betweens aggravate a recorded miss; they do not create it. Any plan that only addresses §7's
+75.7 ms leaves the stated goal unmet.

| # | the win | what is known | what it needs |
|---|---|---|---|
| **1** | **Stop rendering a frame nobody sees.** With the compositor engaged, `updateInterpolationPreviews` renders the derivation for the layer host and `updateSandwich` then blanks it, because `full` already contains that layer. **MEASURED at 26.0 ms of the 100.2 ms** (§7). | The waste is confirmed and both call sites are cited (§7). The fix named there is memoizing `DerivedCelContent.render` on the `identity` it already carries — an identity minted beside the closure it describes, so the key is trustworthy by construction. | Small and self-contained. **Take the local fix, not a third memo** — §5b makes a third claimant on a frame cache after LAYER_COMPOSITING §9.2 and KEYFRAMES §4.6, and building one here first is exactly the mistake §5b exists to prevent. |
| **2** | **Play in-between frames at `.preview` quality.** The cheap tier — one stroked `CGPath` per stroke instead of the full dab walk — is built, shipped, and pinned by `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull`. It is selected only by `isScrubbingInterpolation`, which is **false during playback**. | The tier exists and is tested. The gate is one boolean. | Playback state is `@State` on the timeline *view* (`AnimationTimeline.swift:13-14`), so `CanvasManager` cannot see it. **Hoisting the playback clock onto the model is the prerequisite — and TODO (28) and KEYFRAMES §5 already require it for other reasons.** Also a judgement call the owner may want: preview quality during playback is a visible change. |
| **3** | **Skip the two composite halves that only a stroke can see.** Every tick computes `composite(below)` and `composite(above)` — displayed only mid-stroke — at a **MEASURED 11.0 ms of 22.4 ms** (§3 item 4b). 4b was declined **twice**, both times because making them lazy costs *"a stroke whose first frames have no visible ink, on the most latency-sensitive path in the app"*. **While the playhead runs under a timer, no stroke is starting, so that price does not exist.** | Both the cost and the reason for the two declines are recorded. The argument that the objection lapses during playback is new and is INFERRED. | Same prerequisite as (2): the model must know playback is running. Two wins share one prerequisite, which is what makes the clock hoist the highest-leverage item here. |
| **4** | **The 50% Render Resolution knob does not reach the expensive half.** `DerivedCelContent.render` is documented as rendering **at canvas size, always** — derived geometry is in canvas coordinates and a smaller render would clip rather than scale — and `rasterizeUncached` then draws that full-size image into the reduced bounds. So the artist's existing escape hatch shrinks the composite and buys nothing on the solve or the two canvas-sized vector renders. | The code fact is verified (`CelContentProvider.swift:55-60`, `PixelOps.swift:311-317`). | Unranked because the fix is not obvious: making the derivation resolution-aware is a geometry change, not a plumbing one. Worth knowing before anyone recommends the knob as a workaround — **it is currently a knob that does not do what a user would assume**. |
| **5** | **The one multi-frame image cache that already holds in-betweens is too small.** `PixelOps.rasterizeCache` **already keys on `DerivedCelContent.identity`** (since `531cb0a`) and does retain in-between flattens across frames. But it is FIFO, capped at **24 entries** under `CompositorBudget.textureBudgetBytes` (physicalMemory/16, clamped, = **192 MiB** on a 3 GB iPad 9), shared with every ordinary cel and every layer, and emptied on backgrounding and on memory warning. At 8 MiB a flatten that is ~24 frames of one layer, or **~8 frames of a three-layer document**. | Sizes and policy are code facts. The arithmetic is INFERRED from them. | **This is the honest small version of the owner's model** — "an in-between costs what a cel costs" is true exactly when its picture is materialised once and thereafter addressed. Sizing and scoping an existing cache, not inventing one. Reuse `evictDistantVectorRenderCaches`' distance-from-playhead policy (`vectorRenderCacheLimit = 12`) rather than minting a new one. |

**What not to do.** Do not build KEYFRAMES §4.6's span cache for this: **§4.6's own scope line reads
*"This is machinery for the transformation layer and, later, for export"*, so it was never pointed at
interpolation in-betweens** — shipping stage 6b exactly as specified leaves a generated in-between costing
what it costs today. That is a scope gap, not a schedule gap, and it is the single most surprising thing
found this pass. And do not offer Commit or bake as the performance answer; §2.9 and §6 forbid it in
writing, and it is the very ruling the owner invoked.

**One measurement is owed and its harness already exists.** §7's four rows want re-taking in **Release**,
because §7 now retracts its own transferability claim — the rows are different mixtures of a Swift half
and a GPU half, so the configuration moves the *ratio* as well as the absolutes. The test bodies and run
script written for an attempt that was abandoned under CPU contention survive in the session scratchpad
(`attrib_test_body.swift`, `attrib_test2.swift`, `relperf_run.sh`), so this is a re-run rather than a
rebuild. **Every figure from that attempt is void** — taken between 0% and 34.8% idle, which CLAUDE.md
says returns wrong answers rather than slow ones.

---

## 9. The memory audit, measured on the device (2026-09-02)

The owner's ask, verbatim: *"is memory being allocated nicely? is there any things that are taking much
more memory than they should if they were made smarter? could there be performance gains by doing things
a smarter way?"* [BUGS.md](BUGS.md)'s twelve-site audit is the census; this is what the device says about
it, plus what it misses. Every row below is MEASURED on the **owner's iPad 9 (3 GB, A13), Release**, on
2026-09-02, at `41eafa9` unless another commit is named.

**The device's own numbers, so nothing here has to assume them.** `physicalMemory` 2939 MB;
`os_proc_available_memory()` at rest 1837 MB; `CompositorBudget.textureBudgetBytes` **183.7 MB** — the
docs' habit of writing 192 is the `3 << 30 / 16` arithmetic rather than the number the device produces;
`UIScreen` 768×1024 pt at 2×, i.e. 132 points to the inch.

**The figures were taken at `41eafa9` — the commit the owner's build 1.0.43 is — and they carry to
`9c9d435` because the code they measure did not move.** `git diff 41eafa9 9c9d435 -- Engine/StrokeScratch.swift`
is empty, and `VectorCanvas.render`'s body is byte-identical, lifted into `renderLocked(quality:)` so that
`render(quality:ifStillAtVersion:)` can share it. What stage 2 changed is *where* that body runs, not what
it does. That is stated here rather than assumed, because a figure attributed to the wrong binary is this
repo's most expensive recurring mistake.

**Still open from the twelve at `9c9d435`**: all of them. Two line references have moved and one premise
has: item 1's `renderSources` is now `FrameRecipe.resolveSources` (`Engine/FrameRecipe.swift:88-115`) and
runs off the main actor after stage 2 — **it is still one canvas-sized image per visible leaf, all live at
once, with no budget**, so the site is unchanged and only its thread moved. Item 5's evictor still runs
from `SelectionModels.swift:249` on every `currentFrame` write (`CanvasManager.swift:747`).

### Ranked: what to do, what it costs now, what it would cost smarter

**1. The live-stroke window padded both axes by the longer one — LANDED.** MEASURED before the change:
one screen inch of pen travel at fit zoom held **283.1 MB** at 16383² and 4.4 MB at 2048², against a
stroke bounding box of 0.054 MB and 0.007 MB. Each axis now pads by half of *that axis's* own extent, and
only when the union has actually left it — `StrokeScratch.pad(held:wanted:)`, whose doc comment carries
the amortisation argument per axis.

**The INFERRED ~2.2 MB was optimistic and the corrected figure is 4.42 MB**, from a simulation of the
same gesture against both expressions (300 dabs, 2816 pt of travel, 16383² canvas): 8639×8638 →
8639×134, i.e. 284.67 MB → 4.42 MB, a 64× cut. The simulation reproduces the device's own 8617×8611 to
within 0.3%, which is what licenses it. The gap to 2.2 MB is that padding outsets *both* sides of the
growing axis, so its final extent overshoots the ink by up to ~3× — padding only the side the stroke is
leaving would recover most of that and has not been tried.

**Total copying falls with it and the O(final area) bound survives**: 24.9 M → 1.14 M pixels copied over
that stroke, at 0.98× the final window (it was 0.33×). The one case that copies *more* is a stroke that
turns 90°, where the second axis now has to grow from its own extent: 1.08 M → 2.37 M pixels on an L in a
2048² canvas, against a final window that is still smaller (6.16 → 5.68 MB). Both are simulated, not
measured on the device. Pin:
`BrushEngineLogicTests.testAStraightStrokeGetsABandAndNotASquare`, which fails at 4564 against a bound of
268 if the expression goes back.

**2. Core Animation minified every artwork layer with no mipmaps — LANDED.** MEASURED: a line of the
default 5-point brush width, minified to fit zoom by point sampling, leaves **zero** ink at 4096², 8192²
and 12288², and 800 pixels at 2048²; box-filtered it survives at every size. Every view that showed
artwork set `magnificationFilter` and none set `minificationFilter`, so they all ran CA's default
`.linear` with no mipmap chain. **Nine sites now ask for `.trilinear`** — the layer host's baked and fill
tiers (2), the stroke canvas's picture, live scratch and float (3), the sandwich and onion-skin factories
(2, a pair of views each), the shape preview and the lifted raster piece (2). Sites rather than views
because the first five are per *layer*, which is what makes the mipmaps' cost scale with the stack.
`magnificationFilter` is untouched everywhere, so zoomed-in pixels stay crisp. `SelectionOverlayView`'s collar keeps `.nearest` at both ends because it
is chrome, and that decision is now pinned rather than commented.

**The cost is unmeasured and it is the honest gap here.** A mipmap chain is about a third more texture per
displayed layer, which nothing in the app budgets (item 5 below), and the live scratch rebuilds its chain
per touch-move batch — bounded by the stroke's own window, which item 1 has just made a band. **Nothing
headless can see any of that, and nothing on the device has been asked**: `CanvasLayerFilterLogicTests`
pins the property, not the pixels and not the frame time. **This is the artist-visible one**: it is the
whole of "the brushstroke disappears when you draw" and it was not confined to 16k.

**3. The refit tolerance and the dab spacing are in canvas points, so zooming out multiplies both.** The
owner's own theory of the lag, and it is right. `BrushStamper.stampSpacing = max(brushSize × spacingFraction, 1)`
is in canvas points; the artist works at `fitScale`, so one screen inch is `132 / fitScale` canvas points.
The table below was taken against `StrokeSampleGate`, whose `recordSpacing` was half the dab spacing —
**that gate is gone** (BRUSH.md §12 stage 0), and its replacement moves the *shape* of this item without
removing it: `StrokePathFit`'s 0.25 pt deviation tolerance is also in canvas points, so at `fitScale` 0.047
a tenth of a screen point of input jitter is 2 canvas points, eight times the tolerance, and the fit stops
compressing anything at all. INFERRED from the rule and `fitScale`; nobody has drawn on a 16k canvas and
counted. MEASURED at the default brush (Soft Round, size 5 → 1.0 pt stamp spacing, 0.5 pt record spacing,
**as the gate behaved**):

| canvas | fit | canvas pt per screen inch | dabs per screen inch | stored samples per screen inch |
|---|---|---|---|---|
| 2048² | 0.375 | 352 | 352 | 704 |
| 4096² | 0.188 | 704 | 704 | 1408 |
| 8192² | 0.094 | 1408 | 1408 | 2816 |
| 12288² | 0.063 | 2112 | 2112 | 4224 |
| 16383² | 0.047 | 2815 | **2815** | **5631** |

Eight times the dabs and eight times the stored geometry at 16383² for the same gesture, and the stroke is
sub-pixel while it happens (item 2). Smarter: derive the **refit tolerance** from the live canvas scale
once per stroke — one multiplication, and `StrokePathFit` is reset per stroke already. The dab *spacing*
must stay in canvas points or the ink itself changes. **Cost the owner should weigh rather than a free
win**: a stroke laid down zoomed out is then stored coarser and stays coarser when zoomed in, and
interpolation registration and the vector eraser's capsule chain read the same samples. The owner has
already said a 16k fix is optional (*"the only thing id really be doing in a 16k canvas is idea boards
where the drawings are small compared to the canvas"*), and this is the item that ruling is about.

**4. Vector element undo charges 512 flat bytes for a payload that varies by two orders of magnitude.**
Audit item 8, quantified. `registerVectorElementsUndo` (`Models/CanvasManager+Text.swift:415`) charges
`(old.count + new.count) * 512` while a single `VectorStroke` holds `samples.count × 24` bytes: MEASURED
sample counts above make one screen inch of stroke **16,896 bytes** at 2048² and **135,144 bytes** at
16383² — 33× and 264× the 512 charged for it. `UndoBudget`'s ceiling is therefore not a ceiling on the one element kind whose size is
unbounded. Smarter: charge the strokes' sample bytes and the `.image` elements' pixels. Risk: none
behaviourally — the history gets shorter exactly where it was silently over budget.

**5. Nothing counts what Core Animation holds, and it is up to five canvases per displayed layer.**
MEASURED: displaying one canvas-sized image in a `UIImageView` inside a fit-scaled container walked
`os_proc_available_memory()` down 1841 → 1822 → 1772 → 1579 → 1259 MB across 2048², 4096², 8192² and
12288² — marginal costs of 19, 50, 193 and 320 MB against nominal textures of 16, 64, 268 and 604 MB, so
the same order as the texture and paid *on top of* the `UIImage` the app is holding. (At 16383² the figure
went back **up**, to 1835 MB, because nothing was displayed at all — see BUGS.md's entry of the same
date.) A `LayerHostView` presents
`bakedImageView`, `strokeView` and `fillImageView`, and `StrokeCanvasView` adds its `scratchView` and
`floatView`. `CompositorBudget` bounds the compositor's scratch and the two CPU memos and is silent about
all of it. Audit item 4 (blanked hosts keep every byte) is this seen from one side. Smarter: nil the
contents of views that are blanked or empty rather than masking them, and count what remains against the
same budget. Risk: `setBlanked`'s doc comment records why `isHidden`/`alpha` are wrong there — a nil
`contents` is not, but the hit-testing note has to survive the change.

**6. The flatten memo will hold a gigabyte indefinitely at 16383².** `PixelOps.RasterizeCache.store`
never evicts the entry it just stored, "however far over budget one image on its own puts this"
(`Services/PixelOps.swift:365-370`). That is right at every canvas anyone has measured and wrong at this
one: 1.00 GiB resident against a 183.7 MB budget, dropped only on backgrounding or on the memory warning
§3 item 12 records as never arriving on this device. Smarter: do not memoize an entry that exceeds the
budget on its own — the caller returns it either way, which is the doc comment's own argument, and it is
the *retention* that is wrong rather than the return. Risk: none; it costs a cache miss on a canvas where
the memo could never have held two entries anyway.

**7. The committed re-render is O(canvas area) where a paint stroke's change is O(window).** MEASURED,
one dab on an empty cel: `VectorCanvas.render()` is 3.7 ms at 2048², 5.1 at 4096², 17.4 at 8192², 43.7 at
12288² and **143.5 ms at 16383²**; a bare canvas-sized fill is 4.8 ms and 489.5 ms at the ends. Stage 2
(`7ada46f`) moved this off the main thread, which is the right first move and does not make it smaller —
every stroke, undo, redo and element edit pays it again. Smarter: hold the vector memo as a persistent
`RasterLayerTexture` and composite the finished scratch window into it (`composite(patch:at:)` is already
O(window)), falling back to the full walk when the display list changes in a way source-over cannot
express: an eraser, a non-`.normal` blend run, an element removed, reordered or transformed. Risk:
**medium, and the highest here** — that predicate has to agree with `renderLocalContent`'s three isolation
rules, and disagreeing shows as stale ink on screen while every test stays green.

**8. A canvas-sized `CGBitmapContext` is lazily committed; a Metal shared buffer is not.** MEASURED
sideways rather than head-on: `RasterLayerTexture` stamping one dab into a 16383² tier and reading it back
is **0.9 ms** at every size from 2048² up, because the pages a dab never touches are never faulted in,
while filling the same buffer edge to edge is 489.5 ms. `MetalFillSession` (audit item 3) is the opposite:
~34 bytes per canvas pixel of `.storageModeShared` `MTLBuffer`s (`Engine/MetalFillEngine.swift:300-318`),
resident the moment they are made — 544 MB at 4096² and 9.1 GB at 16383², where `makeBuffer` returns nil
and the session's `guard` turns it into a silent `return nil`. **So the audit's `w·h·4` column overstates
every CoreGraphics site and understates this one**, and a byte budget that treats them alike will budget
the wrong thing.

**What this pass could not measure, and what would.** Residency. `os_proc_available_memory()` did not move
when a fully-written 16383² image was held, which contradicts item 5's display measurement on the same
run; the probe's own timings say the fill had by then stopped happening under accumulated pressure, so
that number is void rather than surprising. Any claim about bytes-resident for the CoreGraphics sites in
the audit should be taken with `task_vm_info.phys_footprint`, not with `os_proc_available_memory()`, and
this section deliberately makes none.

**Three device measurements are owed and the harness for them exists.** A run built against `9c9d435`
was queued and never started: the iPad locked, `xcodebuild` sat on *"Unlock Kevin's iPad to Continue"*, and
nothing on this Mac fixes that. What it would have taken: the committed-render cost with a *realistic* dab
count rather than one dab (item 7's table is the floor, not the figure an artist pays); an isolated
identification of which call in the minify path kills the process at 16383², since the round-2 probe only
established that one of two `CGContext.draw` calls did; and a confirmation, which is only a formality given
the empty diff above, that stage 2's `render(quality:ifStillAtVersion:)` produces the same pixels off the
render queue. None of them changes a conclusion here; all three would sharpen one.

---

## 10. What a baked frame costs on disk and on the clock (2026-09-02)

RENDER §5 stage 4e: *"MEASURE the compression ratio and the decode time on the device rather than
trusting §3.5's expectation of them."* Stage 4a measured a 512² synthetic rect on the simulator, which is
the extreme case at a toy size on the wrong hardware. This is the same store — `Engine/FrameBakeStore.swift`,
LZ4_RAW over tightly-packed BGRA premultiplied-first rows behind a 64-byte header — measured on frames
shaped like the document RENDER §2.8 names, at canvas sizes the owner actually uses.

The harness is `PerfBaselineTests.testWhatOneBakedFrameCostsToCompressStoreAndDecode` and
`…testWhetherAPerRowFilterBeforeLZ4WouldBuyAnything`. Four fixtures: **cel art** (six flat colours in
large hard-edged polygons with real vector ink stamped over them, so the antialiased dab edges LZ4 cannot
match are present), a **hold** (three ink strokes on transparency), a **painted** background (a two-axis
gradient with ±3 of grain) as the honest pessimistic bound, and seeded **noise** as the theatrical one.

**Two kinds of number live below and they do not have the same standing.** The byte counts are exact and
build-independent — the same fixtures produce the same file on any machine, and the simulator and all
three device runs agreed on every one of them to the byte. The milliseconds are hardware and build: **§10.2 is
the owner's iPad 9 in Release**, and the Debug simulator run that preceded it is kept at the end of §10.2
only because of what it got wrong. §1's "the device is ~1.3× the simulator" is a *compositing* figure and
it does not survive contact with this path — **here the device was 2.5–4.9× faster, and the split of the
cost came out reversed**, which is how a 1.6–2.8× win nearly went unnoticed (§10.2 finding 4).

### 10.1 Compression ratio — MEASURED, exact, build-independent

Taken 2026-09-02; the figures are file sizes, so nothing about the host is in them — **the simulator and
all three device runs produced identical bytes in every row, across `4e91777` and `84d2dff`**, which is what
says the fixtures are deterministic and the timings' spread is the machine rather than the measurement.

| canvas | fixture | raw bytes | file bytes | ratio | branch |
|---|---|---|---|---|---|
| 2048×1024 | cel art | 8,388,608 | 154,199 | **54.4×** | LZ4 |
| 2048×1024 | hold | 8,388,608 | 61,955 | **135.4×** | LZ4 |
| 2048×1024 | painted | 8,388,608 | 5,639,767 | 1.49× | LZ4 |
| 2048×1024 | noise | 8,388,608 | 8,388,672 | 1.00× | raw |
| 2048×2048 | cel art | 16,777,216 | 250,947 | **66.9×** | LZ4 |
| 2048×2048 | hold | 16,777,216 | 108,529 | **154.6×** | LZ4 |
| 2048×2048 | painted | 16,777,216 | 11,287,430 | 1.49× | LZ4 |
| 2048×2048 | noise | 16,777,216 | 16,777,280 | 1.00× | raw |
| 4096×4096 | cel art | 67,108,864 | 917,046 | **73.2×** | LZ4 |
| 4096×4096 | hold | 67,108,864 | 443,573 | **151.3×** | LZ4 |

**§2.8's premise holds, and the ratio improves with canvas size rather than decaying.** 54.4× at the
owner's canvas, 73.2× at 4096²: a bigger canvas draws the same picture with more flat pixels in it, so the
incompressible part — the ink's antialiased edges — is a shrinking share. Stage 4a's 108.6× on a 512²
rect was optimistic about *this* document by about 2× and pessimistic about the *trend*.

**The consequence for the store's ceiling, INFERRED from the table.** Ten seconds of 24 fps cel art at
2048×1024 is 240 frames; at 154 kB a frame that is **37 MB**, against 2.0 GB raw. `FrameBakeStore`'s
512 MiB default ceiling therefore holds roughly **an hour** of that material rather than the eleven seconds
the raw arithmetic in RENDER §0 implies — and holds sizeably more than that in practice, because §3.3's
content addressing keeps one file per *hold* rather than per frame, and the hold is the cheapest row in the
table as well as the commonest.

**And the pessimistic bound is not the noise row, it is the painted one: 1.49×.** A painted background —
any smooth gradient — has no exact byte repeat for LZ4 to match and compresses barely at all. A document
whose frames are mostly painted backdrop rather than flat cel would blow the ceiling ~36× faster than the
table's headline suggests. Nothing needs doing about that today; it is written down so that a future
"the bake is filling the disk" report is diagnosed by looking at the artwork first.

### 10.2 Encode and decode — MEASURED on the owner's iPad 9 in **Release**

**Three device runs, and the store changed underneath the second and third.** Two were taken at
`4e91777`, when `FrameBakeStore.load` returned a `CGImage`; the third at `84d2dff`, after RENDER stage
4c replaced that with `loadDecoded` → `DecodedFrame` → `makeImage()`. **The table below is the current
store**; what the earlier pair bought is the subject of finding 4, which is the one worth reading.

Taken 2026-09-02, `-configuration Release`, owner's iPad 9 (A13, 3 GB), Mac idle. Medians of five
repetitions (three at 4096²). Every column is milliseconds. `decode whole` is `loadDecoded`;
**`→ image` is that plus `makeImage()`, and it is the figure the 41.6 ms budget is against**, because a
frame that is not a `CGImage` is not on screen.

| canvas | fixture | encode whole | · BGRA convert | · LZ4 | decode whole | → image | · warm read | · cold read (`F_NOCACHE`) | · LZ4 | · makeImage |
|---|---|---|---|---|---|---|---|---|---|---|
| 2048×1024 | cel art | 12.8 | 1.7 | 3.0 | 1.5 | **1.5** | 0.1 | 0.1 | 1.3 | 0.0 |
| 2048×1024 | hold | 4.7 | 1.7 | 1.3 | 3.1 | **3.1** | 0.0 | 0.0 | 3.0 | 0.0 |
| 2048×1024 | painted | 34.8 | 1.2 | 25.9 | 8.3 | 8.3 | 1.0 | 1.5 | 6.6 | 0.0 |
| 2048×1024 | noise | 29.7 | 1.3 | 8.7 | 2.4 | 2.4 | 1.4 | 2.5 | — | 0.0 |
| 2048×2048 | cel art | 8.8 | 4.3 | 3.3 | 2.8 | **2.8** | 0.1 | 0.1 | 2.3 | 0.0 |
| 2048×2048 | hold | 7.9 | 3.5 | 2.4 | 6.1 | **6.1** | 0.0 | 0.1 | 5.9 | 0.0 |
| 2048×2048 | painted | 76.7 | 3.1 | 48.9 | 19.2 | 19.6 | 2.7 | 3.9 | 15.7 | 0.0 |
| 2048×2048 | noise | 69.7 | 3.3 | 19.0 | 5.2 | 5.0 | 3.3 | 5.7 | — | 0.0 |
| 4096×4096 | cel art | 31.0 | 12.8 | 12.6 | 10.3 | **9.9** | 0.1 | 0.2 | 9.6 | 0.0 |
| 4096×4096 | hold | 26.4 | 13.3 | 10.1 | 24.4 | **24.6** | 0.1 | 0.1 | 23.9 | 0.0 |

`encode whole` exceeds its two split columns by 2–9 ms; that residual is the `Data` assembly and the
atomic file write, which the split does not name and which is the noisiest thing here — it moved by 6 ms
between two runs of the same fixture.

**1. §3.5's own untested claim is confirmed and then some. An 8 MiB frame is 1.5–3.1 ms.** The cold
`F_NOCACHE` storage read inside that is **0.1 ms**, because a 154 kB file is off the NAND before it has
started. That is what the compression buys over and above the disk it saves, and it is why "cold" turns
out not to be a category worth worrying about for artwork: only the incompressible fixtures, whose files
*are* the frame, pay a measurable read at all (2.5 ms at 2048×1024, 5.7 at 2048²).

**2. Decode is proportional to the frame's *pixels*, not to its file — and it is the one finding here
that no change has touched.** The hold is a *quarter* of cel art's file and decodes **slower** at every
size, in every run: 3.1 vs 1.5 ms at 2048×1024, 6.1 vs 2.8 at 2048², **24.6 vs 9.9** at 4096². LZ4
reconstructs the same 64 MiB either way, and a nearly-empty frame is coded as long small-offset matches,
which is every LZ4 decoder's slowest path. **So the decoded ring's "byte budget rather than a count"
(§3.5) has to mean *decoded* bytes** — and, less obviously, the frames content addressing makes cheapest
on disk are the dearest to play. A ring sized on file bytes would hold the wrong number of the wrong
frames.

**3. Every size now fits inside a play interval, and the worst case has real headroom: 24.6 ms against
41.6, 1.70×.** At the owner's own 2048×1024 it is 1.5–3.1 ms and the factor is more than ten. Before
stage 4c the same worst case was 39.3–39.8 ms — **1.05×**, i.e. 96% of the interval consumed by getting
one frame on screen. Play still must not decode on the tick (§3.5 says so and the ring exists for it),
but the margin that makes a one-frame lead sufficient is new as of today.

**4. What stage 4c's copy elimination was worth, measured on both sides of it.** Stage 4e's first two
runs measured the old `load(_:) -> CGImage?`, which decompressed into a `[UInt8]`, did `var copy = bytes`
so a `CGContext` could own the buffer, and then `makeImage()` — **two full-frame copies**. Stage 4c
replaced it with `DecodedFrame`, whose `makeImage()` wraps the same `Data` in a `CGDataProvider` and
copies nothing, and whose `decompress` returns `Data` so there is no `Array`→`Data` copy either.

| canvas | fixture | `load` → `CGImage` at `4e91777` | `loadDecoded` + `makeImage` at `84d2dff` | |
|---|---|---|---|---|
| 2048×1024 | cel art | 4.0 | **1.5** | 2.7× |
| 2048×1024 | hold | 5.0 | **3.1** | 1.6× |
| 2048×1024 | noise | 6.7–6.9 | **2.4** | 2.8× |
| 2048×2048 | cel art | 7.0–7.7 | **2.8** | 2.6× |
| 2048×2048 | hold | 9.8–11.3 | **6.1** | 1.8× |
| 4096×4096 | cel art | 26.4–27.4 | **9.9** | 2.7× |
| 4096×4096 | hold | 39.3–39.8 | **24.6** | 1.6× |

**The `makeImage` column is 0.0 ms at every size**, where the old `CGImage` build was 1.6–2.6 ms at
2048×1024 and 15.3–21.5 at 4096² — larger, at every size, than the codec it sat behind. The LZ4 column
fell too (13.2 → 9.6 at 4096² cel art), which is the `Array`→`Data` copy going away inside `decompress`.
**1.6–2.8× on the whole decode for removing memcpys**, which is the kind of win that only shows up when
the split is measured rather than the total.

**Be precise about what the 0.0 ms is, because "decode to a displayable image" could be read as more
than it is.** Both the old and the new `makeImage` produce a *deferred* `CGImage` — the pixels reach Core
Animation when the layer is composited, and neither figure includes that. What stage 4c actually deleted
is the **eager** full-frame memcpy that ran whether or not the image was ever drawn, and it is only
because the store's rows are already BGRA premultiplied-first — Core Animation's own layout, RENDER §3.5 —
that the deferred half costs nothing extra either. So the table above is the cost of *getting a frame
ready to hand to a layer*, which is the thing the 41.6 ms budget has to cover alongside everything else a
tick does; it is not a claim about the display itself.

**5. The BGRA convert on the *encode* is worth less than a Debug run implied, and mostly at large
canvases.** `bgraBytes` is **1.2–2.4 ms of a 4.7–12.8 ms encode at 2048×1024** — the spread is the
atomic write inside the whole, not the convert — against **12.7–13.8 of 25.2–31.0 at 4096², about half**.
RENDER §3.5's `readBack`-into-`bgra8Unorm` change therefore buys a fraction of the per-frame bake at the
canvas the owner draws on and roughly half at the knob's maximum. Still worth having, since it is a
one-capability-check and it also deletes the per-stroke-lift hitch BUGS.md attributes to the same
convert — but **not the ~2× a Debug run implied.**

**6. The whole bake is affordable at the owner's canvas.** 5–13 ms of store per frame on top of the
composite; 240 frames of a ten-second shot is **under 3 s of encoding** for the whole scene, and §3.3's
content addressing means a held span pays once. The painted and noise rows are 3–7× that, so a
gradient-heavy document is the one to watch on the bake side as well as on the disk side.

#### What the Debug simulator said, and why the split is the part that lied

The same two tests ran first on the iOS 26.5 simulator in **Debug** against the pre-4c store, and that
table is kept because of what it got wrong — not as a data point.

| canvas | fixture | encode whole | · BGRA | · LZ4 | decode whole | · LZ4 | · CGImage |
|---|---|---|---|---|---|---|---|
| 2048×1024 | cel art | 19.0 | 8.8 | 9.7 | 9.8 | 8.9 | 0.8 |
| 2048×1024 | hold | 18.8 | 9.0 | 9.1 | 11.5 | 10.6 | 0.8 |
| 2048×2048 | cel art | 37.2 | 17.8 | 18.6 | 20.0 | 17.9 | 1.6 |
| 4096×4096 | cel art | 145.6 | 70.9 | 72.9 | 78.7 | 72.1 | 6.9 |
| 4096×4096 | hold | 145.7 | 72.2 | 71.2 | 90.5 | 84.2 | 6.7 |

**Every simulator number is slower, which is unsurprising and would have been survivable. What is not
survivable is that the two halves moved in *opposite directions*.** At 2048×1024 cel art, between that
table and the device's pre-4c run: LZ4 decode went 8.9 → **1.4** ms (6.4× *faster*) while the `CGImage`
build went 0.8 → **2.6** ms (3.3× *slower*). So the Debug run reads as "the decompress is 91% of the
decode and the `CGImage` is a rounding error", and the device reads as the reverse. **A session that had
optimised what the simulator pointed at would have spent itself on `libcompression`'s call site and left
finding 4's two canvas-sized memcpys exactly where they were** — which is worth stating plainly, because
finding 4 is a 1.6–2.8× win that the simulator table hides.

The magnitude gap is partly Debug (`bgraBytes` and the old `image(fromBGRA:)` are app code under
`-Onone`, while `compression_decode_buffer` is a system library optimised in either build) and partly
hardware (the copies are memory-bandwidth-bound, and an A13 is well below an M-series Mac there). **That
accounts for the `CGImage` column moving the way it did; it does not account for a 6.4× swing on
`libcompression`, which is unexplained and is not worth explaining, because the device is the number that
counts.** What it does establish reaches past this feature: §1's "the device is ~1.3× the simulator" is a
*compositing* figure and it must not be applied to a codec — **here the device was 2.5–4.9× faster, and
the split came out reversed.** Never extrapolate a split from Debug.

### 10.3 §3.5's contingency, evaluated before anyone builds it: a per-row filter **loses**

RENDER §3.5 ends with *"If the ratio on real documents disappoints, the next step is a per-row Up filter
before LZ4, not a video codec."* The ratio does not disappoint — and had it, **the named next step would
have made it worse**. Byte counts, exact, build-independent, from the same run:

| canvas | fixture | LZ4 alone | Up + LZ4 | Sub + LZ4 |
|---|---|---|---|---|
| 2048×1024 | cel art | 154,135 | 214,358 (**+39%**) | 167,028 (+8%) |
| 2048×1024 | hold | 61,891 | 79,287 (**+28%**) | 63,759 (+3%) |
| 2048×1024 | painted | 5,639,703 | 5,781,663 (+2.5%) | 5,705,178 (+1.2%) |
| 2048×2048 | cel art | 250,883 | 312,069 (**+24%**) | 281,893 (+12%) |
| 2048×2048 | hold | 108,465 | 128,597 (**+19%**) | 111,859 (+3%) |
| 2048×2048 | painted | 11,287,366 | 11,539,451 (+2.2%) | 11,404,944 (+1.0%) |

**Every fixture, both filters, bigger.** The mechanism, INFERRED from the shape of the losses: a filter
helps a coder that models *smooth variation*, and LZ4 does not — it matches exact byte sequences. A flat
region is already one long match, so differencing it to a run of zeros codes to the same size and buys
nothing; but every hard edge, and every antialiased dab boundary, becomes a band of residuals that differ
row by row where the source rows were byte-identical repeats of each other. The loss is therefore largest
exactly where this document has the most edges (cel art, +39%) and smallest where it has the fewest
(painted, +2.5%) — which is the opposite of the ranking the contingency assumed.

**So §3.5's fallback is refuted, not deferred, and the paragraph in RENDER.md has been corrected to say
so.** If the ratio ever does disappoint on a real document, the thing to reach for is a coder that models
prediction error at all (PNG's Paeth *with* DEFLATE, or a real intra codec), not a filter in front of a
match-only coder.

**And the cost side, MEASURED on the device in Release, is not a rounding error — it is the whole
decode over again.** The Up filter is **4.3–7.1 ms** on the way in and **4.4–8.9 ms** on the way out at
2048×1024 (8.8–9.5 at 2048²). The un-filter lands on the decode path, where the whole decode of a cel-art
frame at that size is **1.5 ms** — so adopting it would have multiplied the decode by four or more, in
order to make the file 39% bigger.

### 10.4 What is still owed

**The device answered, so nothing on the measurement itself is owed.** The run did sit on *"Unlock
Kevin's iPad to Continue"* for twelve minutes first — the same wall §9 hit and gave up at — so for the
next session: `xcodebuild` **waits** on that rather than failing, and the run completes by itself the
moment the iPad is unlocked. Queue it and leave it; do not diagnose it as a dead device.

**Two things this pass did not measure, and one that fixed itself.**

- **The owner's own "UI Test" document**, which RENDER §3.5 names. These fixtures are synthetic — designed
  to be the shape §2.8 describes, and honest about their antialiased edges — but a real document is a real
  document, and the ratio it produces is the one that sizes the store's ceiling in practice.
- **A frame that came out of the actual compositor**, rather than one drawn for the purpose. The store's
  own `FrameBakeStoreLogicTests` already round-trips a composited zoo, so the seam is there; what is
  missing is a *big* one, at the owner's canvas, with the layer count RENDER §2.5 names.
- **Nothing on the copy front.** The two redundant full-frame copies this pass found in the old
  `image(fromBGRA:)` were deleted by RENDER stage 4c on the same day, independently, and §10.2 finding 4
  is the before-and-after rather than a proposal. What is left on that path is the LZ4 decompress itself,
  which at 4096² on a hold is 23.9 ms — the largest single number remaining anywhere in this section, and
  the one to look at if a 4K document ever needs more than 1.7× of play headroom.

## 11. How many brush strokes a vector cel holds before drawing stops feeling instant (2026-09-04)

The owner's ask, verbatim: *"one concern i have is how heavy will reconstructing all the brushstrokes
be? say for instance there are 1000 brushstrokes, i can potentially see it causing lagspikes or
crashes due to memory overflow if its not built properly. … The design requirement is this: keep the
brush UX responsive to the user (no lagspike, no latency), while being able to accomidate a lot of
brushstrokes. … I'd estimate the high end to be a couple thousand."*

Measured with `StrokeDensityBench`, which **is merged** and is opt-in behind `PAINTAPP_BENCH` because
it is minutes of wall clock, not because it is disposable — it is the only harness that measures the
render's cost model, and every figure here came out of it. **§11.8 is the answer to this section and
it shipped on 2026-09-04**; §11.1 through §11.6 are the measurement that argued for it, kept in the
form they were taken, with the two rows that moved struck rather than rewritten.

**Provenance for everything below.** Device rows: **MEASURED on the owner's iPad 9 (`iPad12,1`, A13,
3 GB), iOS 26.5.2, Release**, one test class at a time, `-parallel-testing-enabled NO`. Simulator
rows: **MEASURED on an iPad Pro 13-inch M4 simulator, iOS 26.5, Release**, on this Mac at **85.4%
idle with no other `xcodebuild` running** (checked immediately before the run and again after, 78.0%).
Canvas is the owner's **2048×1024** throughout. Fixture: a 400 pt arc, 40 samples, `softRound`
brush at size 18 — `stampSpacing` 1.8 pt, so **236 dabs a stroke**, which the tests report rather
than assume.

### 11.1 The hypothesis is confirmed, and demonstrated rather than read

*A vector cel's memo is all-or-nothing and every edit drops it, so committing one stroke to a layer
holding n re-walks all n and re-stamps every dab.* `VectorCanvas.rasterizations` says whether a call
missed the memo; `lastRenderDabCount` says how much it stamped. Both, on a 40-stroke cel — **identical
on the device and the simulator**:

| operation | re-walks? | dabs stamped |
|---|---|---|
| the layer at rest | — | 9,440 |
| a second `render()` of an untouched cel | **no** | (memo hit) |
| **committing a new stroke at pen-up** | yes | ~~**9,676** = 9,440 + one stroke's 236~~ → **236** since §11.8 |
| an eraser stroke | yes | ~~10,157~~ → **481**, the punch's own dabs, since §11.8 |
| undo (`elements = snapshot` + `bumpVersion()`) | yes | 9,440 |
| a layer transform (`setTransform`) | yes | 9,440 |
| cache eviction (`dropCachedImage`) | yes | 9,440 |
| a freshly loaded cel | cold by construction — `.needsRasterize` | n/a |
| **a zoom** | **no** — `VectorCanvas` has no input a pinch reaches; `render()` is canvas-native | 0 |
| **a render-resolution change** | **no** — `version` and `rasterizations` both unmoved | 0 |

The append row is the whole finding: **9,676, not 236.** A layer transform is the one that costs a
full re-stamp to produce a picture it then merely translates (`invalidateRenderOnly`).

**That finding was acted on and the two struck rows are the result** — §11.8. Every other row still
re-walks and is meant to: undo, a layer transform and an eviction cannot say what moved, so they pay
the full walk. The table is kept in its measured form because *which* edits still cost the whole
layer is the next question anyone asks.

### 11.2 The curve — linear in **dabs**, and the stroke count is not the variable

| n strokes | dabs | iPad 9 re-walk | µs/dab | iPad peak | simulator re-walk | µs/dab | device ÷ sim |
|---|---|---|---|---|---|---|---|
| 100 | 23,600 | 135.0 ms | 5.72 | 18.9 MB | 59.4 ms | 2.52 | (warm-up) |
| 250 | 59,000 | 256.7 ms | 4.35 | 19.4 MB | 154.6 ms | 2.62 | (warm-up) |
| 500 | 118,000 | 376.7 ms | 3.19 | 19.4 MB | 295.3 ms | 2.50 | 1.28 |
| **1000** | 236,000 | **744.8 ms** | 3.16 | 19.7 MB | 568.7 ms | 2.41 | **1.31** |
| **2000** | 472,000 | **1489.4 ms** | 3.16 | 20.2 MB | 1132.3 ms | 2.40 | **1.32** |
| 4000 | 944,000 | 2976.8 ms | 3.15 | 22.9 MB | 2263.5 ms | 2.40 | 1.32 |
| 8000 | 1,888,000 | 5949.1 ms | 3.15 | 26.5 MB | 4513.0 ms | 2.39 | 1.32 |
| 16000 | 3,776,000 | 11,912.8 ms | 3.15 | 41.3 MB | — | | |
| 32000 | 7,552,000 | 24,042.8 ms | 3.18 | 71.1 MB | — | | |
| 48000 | 11,328,000 | 35,846.0 ms | 3.16 | 80.1 MB | — | | |

**It is a straight line, on both machines, over a 480× range of n.** 3.15–3.18 µs a dab on the iPad
from n = 500 to n = 48,000; the first two rows are one-off allocation faulting, not curvature. Nothing
departs from linear and nothing is superlinear anywhere.

**§1's ~1.3× device multiplier holds on this path too, and tightly: 1.31–1.32 for every n ≥ 1000**
(1.28 at 500). That is worth having beyond this task — §1 established it for *compositing* and §10.2
found it inverted for the bake codec, so this is a third path and it agrees with the first. **And it
holds on the incremental append as well, 1.30–1.32, which it had no obvious reason to** — that path
is three quarters buffer copy rather than ink (§11.8, §11.9).

**This table's device column was re-taken on 2026-09-04 and it has not moved**: 1480.2 / 1481.4 ms at
n = 2000 against the 1489.4 above, and 2958.4 / 2959.1 against 2976.8, across a run of merged stages
that included one making an image dab 2.1× a round one. §11.8 carries the re-run.

**The owner's unit is strokes; the machine's unit is dabs, and only dabs.** MEASURED on the device:
**3,200 zig-zag strokes carrying 7,667,200 dabs cost 23.52 s (3.07 µs/dab)** against **32,000 strokes
carrying 7,552,000 dabs at 24.04 s (3.18 µs/dab)** — a tenth as many strokes, the same ink, the same
time. There is no meaningful per-stroke fixed cost. So *"how many strokes can I have"* has no answer
on its own; **at this brush, one stroke is 236 dabs and 0.75 ms on the iPad**, and halving the brush
size doubles the strokes that fit in any budget.

*A refutation this section nearly published.* The first attempt at that experiment used a single
straight 8,000 pt path on a 2,048 pt canvas. Most of its dabs fall off-canvas, where CoreGraphics
rejects them nearly free: it read 15.1 M dabs at **0.59 µs** and looked like proof of a large
per-stroke fixed cost. The ratio was the clipping. The corrected fixture zig-zags inside the canvas
and lands on 3.07. `PerfBaselineTests.syntheticStroke` already carries a `passes` knob for exactly
this reason.

### 11.2a BRUSH.md §12 stage 7 put a modulation matrix on this path, and it cost 35%

**MEASURED on this Mac's simulator, same fixture, same brush, same day, `origin/main` at `bc9982f`
against `tmp/matrix`** — `PaintSoftwareUITests/DabCostBench`, which exists so this can be re-taken
rather than re-derived:

| | walk only | whole re-walk, rasterization included |
|---|---|---|
| before — `BrushDynamics`' two blends | **0.845 µs/dab** | **4.018 µs/dab** |
| after — §6's matrix, the same preset as two rows | **2.122 µs/dab** | **5.437 µs/dab** |
| | **+1.28** | **+1.42, or +35%** |

**Say it plainly: this is a regression to the constant §11.2 is built on, and it is a finding rather
than a failure.** The incremental append's whole justification rests on 3.16 µs/dab being flat and
small; INFERRED from §1's 1.3× device multiplier holding on this path, the owner's iPad now pays
about **4.3 µs a dab** for a two-row preset. At their measured 236 dabs a stroke that is 1.01 ms a
stroke against 0.75.

**It is attributed, not guessed** — the same bench, one row at a time:

| brush | µs/dab (walk only) | marginal |
|---|---|---|
| no rows at all | 0.308 | — |
| one row, no curve | 1.099 | **+0.79 a row** |
| two rows, no curves | 1.892 | +0.79 |
| two rows, one carrying a ramp (`hardRound`) | 2.122 | +0.23 for `AnimationCurve.evaluate` |
| three rows including §2.18's dropout | 3.19 | +1.07 (a draw and a skip test) |
| six rows across five sensors | 5.44 | +0.85 a row |

**So the cost is per *row*, ~0.79 µs, and the curve is only a quarter of it.** Two things make up the
rest, and the split between them is INFERRED from the shape rather than profiled: a `.random` row costs
**+0.49** against a `.pressure` row's **+0.79**, and the difference is the funnel's channel read —
`StrokeSensors.channelValue` interpolates two stored samples, and a two-row preset now does that
**twice a dab** where the old path did it once. The remaining ~0.5 µs is ARC: `BrushModulation` owns a
`ResponseCurve` owns an `AnimationCurve` owns a `[Key]`, so materialising one row out of the array in
the hot loop is a retain/release pair per row per dab.

**Two candidate fixes, neither built, and the reason is a decision rather than an oversight.**

1. *Memoise the funnel per dab.* Rows sharing an input would read the channel once. Bounded saving —
   about 0.3 µs on a two-row preset, since it removes one of the two reads and nothing else.
2. *Take the heap array off the hot row.* Storing a small curve inline would remove the ARC, and it is
   the larger term. It also un-does BRUSH.md §7's *"reusing it is what keeps this from being a second
   curve implementation"*, which is the property the owner asked for first: *"I want a clean and well
   designed architecture first, which cleanly replaces the old one."* Trading it for ~0.5 µs a row is
   their call, not a worker's.

**And one micro-optimisation was tried and refuted, which is worth not re-trying.** `@inline(__always)`
on `dabValues`, `contribution` and `ResponseCurve.value(at:)`, plus iterating the rows by index instead
of `for row in`, made **every** row of the table 8–10% *worse* — including the zero-row case, which
those annotations cannot reach. That uniformity is the tell that it was machine noise on top of no
gain, and it is why the numbers above were taken on an idle machine under `simlock`.

**The bench's own numbers are not §11.2's**, and that is deliberate rather than sloppy: it walks a
different corpus into a 2048² canvas, so 4.018 is not the 2.40 §11.2 measured. What is comparable is
the **ratio between two builds of the same bench**, which is what the table reports.

### 11.2b BRUSH.md §2.28 made the row a chain, and it cost 3–4% of a dab

**MEASURED on this Mac's simulator, `4791204` and then `860a4a0` against `tmp/chain`, each pair taken on
a dedicated device back to back under `simlock` with nothing else running** — the same `DabCostBench`,
which exists so this can be re-taken rather than re-derived. §2.28 turned `Brush.dabValues`' one pass
over a flat array of *(input, curve, amount, second)* rows into a **nested walk** over a chain's ordered
modules, and §2.29 then gave every `.scale` a `ResponseCurve` of its own; the rulings were accepted on
the understanding that the cost would be measured rather than assumed.

**Two independent pairs, so the columns carry both.** The second was taken after §2.29 landed and this
branch rebased onto it, and it says the second curve added nothing measurable.

| brush (walk only) | before | after | Δ |
|---|---|---|---|
| no rows at all | 0.304 / 0.320 µs/dab | 0.305 / 0.312 | **flat** |
| one row, no modules | 1.161 / 1.157 | 1.155 / 1.146 | −1% |
| two rows, no modules | 2.002 / 2.047 | 2.037 / 2.002 | flat |
| `hardRound` — two chains, one carrying a curve ramp | 2.260 / 2.288 | 2.387 / 2.379 | **+4.0 to +5.6%** |
| six chains, one module each | 5.781 / 5.716 | 6.121 / 6.179 | **+5.9 to +8.1%** |
| §2.18's dropout | 3.412 / 3.435 | 3.656 / 3.622 | +5.4 to +7.2% |
| a colour-jittering brush | 2.811 / 2.771 | 3.121 / 3.169 | +11 to +14% |
| **the whole re-walk, rasterization included** | **5.652 / 5.615** | **5.893 / 5.803** | **+3.3 to +4.3%** |

**So a module costs about 0.06 µs and an empty chain costs nothing at all** — the loop over `modules` is
not entered for a chain with none, which is why the unmodulated and single-bare-row rows are flat to
within noise in both pairs. The shipped presets each carry exactly one module (the curve ramp that used
to be the `curve` field), and the whole-dab cost of the feature to them is **+0.19 to +0.24 µs, 3–4%**.

**Two new bench cases, and they are the ones to watch.**

| | µs/dab, walk only |
|---|---|
| six chains carrying **eleven** modules between them | **10.98 / 10.99** |
| a randomiser at **1** octave | 2.927 / 2.919 |
| …at **4** | 3.771 / 3.734 |
| …at **8** (the cap) | 4.602 / 4.710 |

**An octave costs 0.24–0.26 µs**, which is one more `DabRandom.unit` — two splitmix64 avalanches and a
smoothstep — and it is the steepest thing an artist can buy on this path: eight octaves is +1.7 µs a
dab, about a third of a whole dab. That is a *deliberate* purchase with a slider beside it, and it is
what the type's cap of 8 exists to bound; §2.28's own argument stands, that one randomiser with a count
is cheaper than the three rows the same roughness needed before, since each of those paid a chain's
sensor read as well as its hash.

**Say plainly what is not known**: the *eleven-module* number is a shape nothing in the shipped set has,
built to find the slope rather than to describe a brush, and no artist has yet made one. INFERRED from
§1's 1.3× device multiplier, the owner's iPad pays about **7.7 µs a dab** for that brush against 3.1 for
a shipped preset.

**The variance is stated because this section has been wrong about it before.** A pass taken while
another session's work crept back onto the machine put the *base* commit at 8.882 µs on the whole
re-walk against its own 5.652 twenty minutes earlier — a 57% swing with nothing changed — while the
`tmp/chain` numbers repeated to within 1% across the same two passes. The table above uses only the
pairs where both trees were measured back to back on a quiet machine; CLAUDE.md's *"a run measured
against a busy machine is not a measurement"* is why the other one is named here rather than used. One
cell is still an outlier and is left visible rather than dropped: `no rows` read **0.521** on the second
base pass against 0.304, 0.307 and 0.320 on three others, and it is the first test of that run.

### 11.3 The upper bound: nothing breaks, and memory is not the story

**Memory is a non-issue at every n the owner will reach.** Stroke geometry is
`samples × 24 bytes` — **0.9 MB at 1,000 strokes, 7.3 MB at 8,000, 29.3 MB at 32,000** — against one
canvas-sized bitmap at 8 MB.

**BRUSH.md §12 stage 4 widened the record and left that figure standing for most strokes.** A stroke's
samples are struct-of-arrays now (`StrokeSamples`), so the resident cost is 16 bytes of position plus
8 per channel the stroke actually carries: a pressure-only run is **24 bytes a sample, exactly what it
was**, and a Pencil stroke carrying Δt and both tilt channels is **48**. A finger-drawn stroke keeps
none of pressure or tilt — all three quantise to their neutrals and are dropped at commit — so the
ceiling is 1.8 MB a thousand strokes and the common case has not moved. On disk it is 8 bytes a sample
against 5 for a Pencil, and **5 for a finger, MEASURED off a saved project**: the run's channel-set byte
comes back `0x04`, Δt alone. On the wire the full record is **10.785 B a sample against 6.743**; BRUSH.md
§5.1 carries both. The iPad's whole footprint holding a 48,000-stroke cel *and* rendering
it is **80 MB**, on a device whose undo budget alone is 192 MiB (`UndoBudget`, §9). The render adds
essentially nothing: peak tracks the geometry.

**The largest display list actually rendered on the owner's device is 64,000 elements at 103.7 MB**
(64,000 short strokes, 320,000 dabs, 1.52 s). So a 64,000-element display list is not too big; it is
only too slow when its strokes are full length.

**The one SIGKILL is the test harness, not the app**, and the evidence is the point rather than the
conclusion. `testHowFarItGoesBeforeSomethingBreaks` was killed at n = 64,000 (`Test crashed with
signal kill`), which reads as jetsam. Three measurements say it is not:

* 64,000 elements at **103.7 MB** rendered fine when the strokes were short (1.52 s) — so it is not
  the size of the display list;
* 48,000 full-length strokes rendered fine at **80.1 MB** in **35.85 s** — so it is not 80 MB;
* the 23.5 s corrected-arm-B test **passes alone and is killed when it follows a 35.8 s test in the
  same process** — so the kill tracks *cumulative CPU-bound wall clock in the runner*, not the work.

Every kill is on the far side of ~45 s of unyielding CPU in one XCTest process; every run whose
cumulative blocking work stayed under ~36 s passed. **No number here is a memory ceiling, and the app
was never the thing killed.** A run that intends to go past ~30 s of synchronous work should be split
across test methods and processes.

**So the honest answer to "what is the upper bound": there isn't a crash to find.** The cel degrades
linearly and becomes unusable to draw on long before anything runs out.

### 11.4 The number the requirement is written in: pen-up to pixels

The shipped sequence is `endVectorStroke` → `addStroke` → `refreshDisplay` → `startVectorRender` on
`StrokeCanvasView.renderQueue`, so the re-walk is **off the main thread** (RENDER.md §2.13). Both
halves, MEASURED at each n:

| n strokes | main thread at pen-up (iPad 9) | background re-walk (iPad 9) | main thread (sim) | background (sim) |
|---|---|---|---|---|
| 100 | 1.205 ms* | 76.7 ms | 0.087 ms | 62.2 ms |
| 250 | 0.075 ms | 187.0 ms | 0.062 ms | 142.7 ms |
| 500 | 0.152 ms | 372.9 ms | 0.120 ms | 283.3 ms |
| **1000** | **0.302 ms** | **744.6 ms** | 0.198 ms | 564.8 ms |
| **2000** | **0.568 ms** | **1488.8 ms** | 0.405 ms | 1134.7 ms |
| 4000 | 1.138 ms | 2977.2 ms | 0.830 ms | 2261.7 ms |
| 8000 | 2.646 ms | 5955.1 ms | 2.062 ms | 4561.6 ms |

*\*first row of the run; the 250-row's 0.075 ms is the settled figure.*

**There is no main-thread lag spike, at any n the owner will reach.** Committing a stroke to a
4,000-stroke layer costs the main thread **1.1 ms**. The app does not freeze, and it will not; the
2026-08-20 work (items 9(b), 11) and RENDER §2.13 already took that cost off the main thread. **Two
thirds of this question is already answered in the app's favour and the owner should be told so.**

**What is left is latency, and it is entirely the background re-walk.** At the owner's *current*
190 strokes a cel (§3 item 14, the cel read off their device) that is **~142 ms** (INFERRED at the
measured 3.16 µs/dab, 236 dabs a stroke). In their own terms, on their own device:

| budget | dabs | strokes at this brush |
|---|---|---|
| one 60 Hz frame, 16.7 ms | 5,285 | **~22** |
| one 24 fps frame, 41.6 ms | 13,165 | **~56** |
| "instant", 100 ms | 31,646 | **~134** |
| 250 ms | 79,114 | ~335 |
| 500 ms | 158,228 | ~670 |
| **1 s** | 316,456 | **~1,340** |
| 2 s | 632,911 | ~2,680 |

(INFERRED from the MEASURED 3.16 µs/dab; each row is arithmetic over it.)

**And the artist sees that latency as their ink disappearing, not as a slow refresh.** READ from
`StrokeCanvasView`, not measured, and it wants a minute on the device to confirm: at pen-up the
finished stroke stays visible as the `scratch` overlay while the re-walk runs
(`scratchIsHeldForRerender`), which is correct. But `scratch`'s `didSet` releases that hold when a
*new* scratch is made — deliberately, and the doc comment says why. So if the artist starts stroke
n+1 before stroke n's re-walk has landed, **stroke n is not on screen at all** until it does: the base
slot still holds the pre-stroke picture and the scratch now shows only the new stroke. The window is
exactly the re-walk above — **0.74 s at 1,000 strokes, 3.0 s at 4,000** — and a person inking line art
puts strokes down far faster than that. **This is what "lagspike" will mean to the owner even though
no thread ever blocks**, and it is invisible to every timing in this section.

**That suspicion was chased down and it is real** — [BUGS.md](BUGS.md), 2026-09-04, where the reading
is completed by tracing every path that repaints the base rather than only the one that releases the
hold. §11.8 shrank the window it opens from 1.1 s to 2.6 ms at 2,000 strokes and did not close it,
and no small fix does: there is one scratch view, so holding the old scratch does not display it.

### 11.5 The other half of "memory overflow": undo, which does scale with n

`StrokeCanvasView.registerVectorUndo` retains the display list twice per stroke and charges the
history `(from.count + to.count) * 512` bytes, so both grow linearly with the strokes already there.
MEASURED on the iPad 9, 30 undo steps deep, against `UndoBudget.maxCostBytes` = **192 MiB** there:

| n strokes | really retained, per step | *charged*, per step | undo steps inside the budget |
|---|---|---|---|
| 190 (the owner's density) | ~0.003 MB | 0.19 MB | **1,032** |
| 500 | 0.05 MB | 0.49 MB | 392 |
| 1000 | 0.30 MB | 0.98 MB | **196** |
| 2000 | 0.55 MB | 1.95 MB | **98** |
| 4000 | 0.71 MB | 3.91 MB | **49** |

**The charge is 3–6× what an entry really holds**, because consecutive snapshots share every stroke's
`samples` array by copy-on-write and only the element array is duplicated. So undo depth is trimmed
harder than the memory warrants — at 4,000 strokes the artist gets **49 undo steps** where the bytes
would allow a few hundred. Nothing overflows; the depth quietly shortens. The `512` is a per-element
proxy nobody has ever measured against the thing it proxies, and this is the measurement.

### 11.6 What making the append incremental would buy — a throwaway spike, not a proposal

On a layer of n strokes: (a) the shipped full re-walk of n+1, against (b) stamping only the appended
element through `renderIsolated(ids:)` and drawing it over the standing cached image. **The two arms
were compared pixel for pixel** — mean channel difference **0.0001–0.0002 of 255** — because a spike
whose pixels differ is measuring two different things.

| n strokes | full re-walk (iPad 9) | incremental (iPad 9) | prize | simulator |
|---|---|---|---|---|
| 500 | 373.9 ms | **9.8 ms** | **38×** | 288.8 → 6.6 ms, 44× |
| 2000 | 1491.6 ms | **7.3 ms** | **206×** | 1661.0 → 9.4 ms, 177× |
| 4000 | 2985.6 ms | **7.9 ms** | **377×** | 3157.4 → 15.1 ms, 209× |

**The incremental arm is flat in n** — about 8 ms, which is two canvas-sized blits (8 MB apiece) plus
the new stroke's own 236 dabs. So the prize is not a constant factor, it is the removal of the slope:
pen-up-to-pixels would stop depending on how much is already on the layer, and the 1,340-stroke
"one second" line in §11.4 would move out to wherever the artist's document ends.

**This was merged on 2026-09-04 and §11.8 re-measures it on the render the app actually has.** Read
this section for the constraint, not for the numbers — the shipped path is 2.4-5.6x *faster* than the
spike arm above and byte-identical rather than 0.0001-of-255 away, because it stamps the new dabs
straight into a copy of the standing picture instead of into a bitmap of their own. The constraint
that made this a spike rather than a patch: the display list is **not associative in general**. An `.erase` stroke
composites `destinationOut` against everything beneath it and a run of blend-mode strokes is wrapped
in one transparency layer, so an element appended into or after either is not equivalent to
compositing it over the finished picture. It is equivalent exactly under source-over — which
`renderLocalContent`'s own rule 2 already states — and that is the case timed above. A real
implementation needs the memo to record *what it is a picture of*, and to fall back to the full walk
whenever the appended element is an eraser, carries a blend mode, or lands anywhere but the end.

### 11.7 The short answer for the owner

* **No lag spike.** Committing a stroke to a 4,000-stroke layer costs the main thread 1.1 ms on their
  iPad. The app does not freeze at any density measured.
* **No crash, and no memory problem.** 48,000 strokes render in 80 MB. Geometry is ~0.9 MB per
  thousand strokes. The one SIGKILL is the test runner's, and the evidence for that is in §11.3.
* **There was latency, it was entirely the re-walk, and it started biting far below "a couple
  thousand".** Their 190-stroke cel was ~142 ms behind the pen; 1,000 strokes was 0.74 s and 2,000
  was 1.5 s, on their own hardware. **Fixed on 2026-09-04 — §11.8.** Committing a stroke now costs
  what that one stroke costs and nothing for the ones already on the layer, so every row of the
  budget table above stops depending on n. The edits that still pay the full walk are undo, a layer
  transform, an eviction and anything inserted into the middle.
* **Strokes are the wrong unit.** 3.16 µs a dab is the whole cost model; at their brush that is
  236 dabs and 0.75 ms per stroke, and a smaller brush buys proportionally more strokes. **A pen-up
  now costs that stroke and nothing for the ones already on the layer** — MEASURED on their iPad at
  **3.4 ms**, of which 0.75 ms is the ink and the rest is one canvas-sized copy that does not care
  how much is on the layer (§11.9). It was 1.48 s at 2,000 strokes.
* **The one thing they may still see is a finished stroke blinking out** if they start the next one
  before the first has rendered — [BUGS.md](BUGS.md). On their own iPad the window is **3.4 ms rather
  than 1.48 s** (§11.8, at 2,000 strokes), so in practice it should be unreachable, but it is not
  closed.

### 11.8 What it bought, measured on the shipped path (2026-09-04)

§11.6 priced a spike. This is the same measurement against the render that merged —
`VectorCanvas.Damage`, which is what each of the sixteen mutation sites now says about itself, and
`appendableBase(quality:)`, which is what `renderLocked` does with it. Arm (a) is a full re-walk of
*n+1* forced with `bumpVersion()`, which is what an **undo** still costs; arm (b) is the shipped
pen-up, `addStroke` then `render()`, median of three consecutive appends.

**MEASURED on an iPad Pro 13-inch M4 simulator, iOS 26.5, Release, 2048x1024**, on this Mac at 93.1%
idle with no other `xcodebuild` running (checked immediately before). `StrokeDensityBench`'s
`testWhatTheIncrementalAppendBought`.

| n strokes | full re-walk | shipped append | prize | dabs stamped, full | dabs stamped, append | same bytes? |
|---|---|---|---|---|---|---|
| 500 | 283.6 ms | **2.71 ms** | **105x** | 118,236 | **236** | yes |
| **2000** | 1129.6 ms | **2.57 ms** | **439x** | 472,236 | **236** | yes |
| 4000 | 2252.6 ms | **2.71 ms** | **832x** | 944,236 | **236** | yes |

**Flat at 2.6-2.7 ms across an 8x range of n, and it beats the spike it was priced from** - 6.6, 9.4
and 15.1 ms for the same three rows in §11.6, and the spike's own figure *grew* with n while this one
does not. The reason is allocation: the spike stamped the new element into its own canvas-sized
bitmap through `renderIsolated(ids:)` and then composited two full images into a third, which is
three canvas-sized buffers and two full-canvas draws. The shipped path draws the standing picture
into one new context and stamps the new dabs straight in - one buffer, one draw.

**The dab column is the honest one and it is what the logic tier asserts**, because milliseconds are
about this Mac and 236 is about the algorithm: a stroke's own 236 dabs, whatever the cel already holds.

**Byte-identical, at zero tolerance, against a canvas that cannot have taken the fast path** - not
the spike's 0.0001-0.0002 of 255. There is nowhere for a rounding difference to enter when the new
dabs go into a copy of the standing bitmap rather than through an isolated layer, and
`IncrementalAppendLogicTests` pins that at 128x96 and again at the owner's own 2048x1024.

**And the device row, taken 2026-09-04 on the owner's own iPad.** The run above had none - the iPad
answered *"Unlock Kevin's iPad to Continue."* This is it, on the same fixture, **MEASURED on the
owner's iPad 9 (`iPad12,1`, A13, 3 GB, iOS 26.5.2, arm64), Release, `test-without-building`,
`-parallel-testing-enabled NO`**, two independent runs listed as `run 1 / run 2` rather than averaged.
The Mac was at 75-81% idle with one other session's `xcodebuild` alive, which for once does not need
a caveat and has its own operand below.

| n strokes | full re-walk, iPad 9 | §11.2's row | shipped append, iPad 9 | prize | append, sim | device ÷ sim |
|---|---|---|---|---|---|---|
| 500 | 371.9 / 387.4 ms | 376.7 | **4.41 / 3.80 ms** | ~93x | 2.71 | (1.51) |
| **2000** | 1480.2 / 1481.4 ms | 1489.4 | **3.33 / 3.45 ms** | ~437x | 2.57 | **1.32** |
| 4000 | 2958.4 / 2959.1 ms | 2976.8 | **3.61 / 3.44 ms** | ~840x | 2.71 | **1.30** |

`dabsFull` was 118,236 / 472,236 / 944,236 and `dabsIncremental` **236** on every row of both runs,
and both runs were byte-identical against the cold canvas. `totalTestCount: 1, skippedTests: 0` off
the xcresult, on `deviceName: Kevin's iPad`, so the bench ran rather than skipped.

**§11.2's device rows hold, and the agreement is the tightest this file has recorded** - 371.9 and
387.4 against 376.7, 1480.2 and 1481.4 against **1489.4**, 2958.4 and 2959.1 against **2976.8**: 0.6%
at n = 2000 and 0.6% at n = 4000, on figures taken a run apart at a different commit. Per-dab that is
3.13-3.15 us against §11.2's 3.15-3.19. **Several stages have merged since those rows were taken,
including one that made an image dab 2.1x a round one, and the vector stroke walk did not move.**
That agreement is also what says this run was not distorted by the other session's build: the timed
work is the A13's, `xcodebuild` only streams the log, and the calibration rows were taken on an idle
Mac.

**The device ÷ simulator ratio for the append is 1.30-1.32 - the same 1.31-1.32 §11.2 measured for
the re-walk, and there was no reason to expect it.** The re-walk is ink and the append is three
quarters buffer (§11.9), so this is the M4's memory-bandwidth lead over the A13 coming out at
essentially its compute lead on the same path. It is MEASURED, not explained, and it is the third
path on which §1's ~1.3x holds against §10.2's one inversion. The n = 500 row reads 1.51 and is
excluded: it is the first row of the run, which is where §11.2 already puts its warm-up.

**The 0.75 ms this section inferred rather than measured was right, to the two figures it was
quoted at.** §11.9 measures one stroke's ink on the device at **0.75 ms at n = 2000 and 0.76 ms at
n = 4000**, against the 236 x 3.16 us = 0.75 ms this paragraph used to carry as INFERRED. The refusal
to infer the *rest* was also right, and §11.9 is that term.

To re-take either row:

```bash
TEST_RUNNER_PAINTAPP_BENCH=1 xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -configuration Release -destination 'platform=iOS,id=E3B83820-DF74-5042-B52B-0D5BA17E4877' \
  -only-testing:PaintSoftwareUITests/StrokeDensityBench/testWhatTheIncrementalAppendBought \
  -parallel-testing-enabled NO -allowProvisioningUpdates -derivedDataPath build/DerivedDataDevice
```
**The `TEST_RUNNER_` prefix is load-bearing** and cost this section a run: a bare `PAINTAPP_BENCH=1`
sets the variable for `xcodebuild`, not for the runner process, so every test skips and the run
reports `** TEST SUCCEEDED **` with two skips and no `STROKE BENCH |` lines. The banner-versus-count
trap in one more costume.

**Run the two bench tests as separate invocations, not one.** `testWhatTheIncrementalAppendBought`
alone is **29.3 s of unyielding CPU in the runner** on the iPad 9 and §11.3 measured the XCTest
watchdog's SIGKILL somewhere past ~45 s cumulative; adding §11.9's 5.6 s to the same process spends a
third of the remaining margin for nothing. `build-for-testing` once, then one
`test-without-building` per test, which is also what makes the two comparable.

**What still costs the whole layer, deliberately.** Undo and redo, a layer transform, a cache
eviction, an element inserted anywhere but the end, a suppressed element, and an appended stroke
carrying a blend mode. The first three cannot say what moved; the last three *can* and are still
wrong to fast-path, because the display list is not associative - §11.6. Middle-of-list edits (the
eraser's cut and split modes, a lasso move, Clear, Recolour) are the dirty-rect version and are their
own item in [TODO.md](TODO.md); `Damage` is shaped so a `case region(CGRect)` can be added without
revisiting a single mutation site.

**One cost, and it is transient.** Between an append and the render that consumes it the cel holds the
standing picture alone - 8 MB at 2048x1024 - where the shipped code held nothing. It is the bitmap the
old path was about to allocate anyway, it is released the moment the render lands, and `hasCachedImage`
counts it so eviction can see it. The window it is held for shrank from 1.1 s to 2.6 ms at n = 2000
on the simulator, and **from 1.48 s to 3.4 ms on the owner's own iPad**, so this is strictly less
memory-over-time than before.


### 11.9 Where the append's milliseconds go: three quarters of it is moving 8 MB (2026-09-04)

§11.8 refused to infer this term and it was right to: it is canvas-sized buffer work, and §10.2 had
already caught that class of ratio **inverted** between this Mac and the device. **MEASURED on the
owner's iPad 9 (`iPad12,1`, A13, 3 GB, iOS 26.5.2), Release, Mac at 75.5% idle**, canvas 2048x1024,
by `StrokeDensityBench.testWhereTheAppendsMillisecondsGo`.

**The instrument is a slope rather than a stopwatch around a private method**, because there is no
seam between the blit and the walk and cutting one in would measure the seam. An append costs
`fixed + dabs x perDab`, and only the walk depends on how much was appended - so appending *k*
strokes before a single `render()` multiplies the ink by *k* and moves nothing else. Five points,
k = 1, 2, 4, 8, 16, median of three at each, least squares:

| n strokes | fixed cost | us/dab | one stroke's ink | one stroke, total | buffers' share | R² |
|---|---|---|---|---|---|---|
| 500 | 2.97 ms | 3.64 | 0.86 ms | 3.83 ms | 78% | 0.9968 |
| **2000** | **2.30 ms** | **3.17** | **0.75 ms** | **3.04 ms** | **75%** | 0.9999 |
| 4000 | 2.57 ms | 3.22 | 0.76 ms | 3.33 ms | 77% | 0.9997 |

**So the answer is ~2.5 ms of buffers against ~0.75 ms of ink: the append is three quarters memory
traffic and one quarter brush.** Which is the opposite of everything else in §11, where the dab count
was the only variable that mattered - and it is what makes the append flat: the term that dominates
it does not know how much is on the layer.

**Two operands, and they agree.** The slope is an independent re-derivation of §11.2's 3.16 us/dab,
off a different fixture on a different code path, and it lands at **3.17 and 3.22** at n = 2000 and
4000. The intercept has its own second reading - a **replica**, not the shipped path: a bare
`UIGraphicsImageRenderer` of the canvas's size with a standing picture drawn 1:1 into it, and then
the same with nothing drawn into it at all.

| replica arm | seconds |
|---|---|
| the 8 MB context, allocated and turned into a `CGImage`, nothing drawn | **0.57 / 0.59 ms** |
| the same, with the standing picture blitted 1:1 into it | **2.14 / 2.12 ms** |
| **the blit alone**, by difference | **1.55 ms** |

2.13 ms of replica against a 2.30-2.97 ms intercept, so **the buffer story accounts for essentially
all of the fixed cost** and the 0.2-0.8 ms left over is the rest of `renderLocked` - the lock, the two
memo checks, the tail slice, and releasing the previous 8 MB image. Both numbers are physically
sensible on an A13: an 8 MB zero-fill at 0.57 ms and a 16 MB read-plus-write at 1.55 ms are ~14 and
~10 GB/s.

**The two replica arms are a pair on purpose and the pair refuted a hypothesis.** One throws each
image away so the allocator hands back the same warm slab; the other retains all seven so every
iteration faults in pages it has never touched, which is what the shipped append does - the base it
draws *from* is the previous render's output and is still live while the new context is allocated.
**They measure the same, 2.14 against 2.12 ms**, so first-touch faulting is not in this number and a
warm-buffer replica is not flattering itself. That was the standing explanation for a 2.1x gap in the
first version of this fixture, and it was wrong: the gap was a four-point fit at R² 0.978, and the
fifth point closed it.

**`appendPreservesTheWalk`'s O(n) scan is below the noise, so "flat in n" is exactly true rather than
true to within it.** That backward-and-forward scan over the merged paint run is the only term left in
an append that grows with the layer, and if it mattered the fixed cost would rise across the table.
It reads **2.97 / 2.30 / 2.57 ms** at 500 / 2000 / 4000 - not monotone, and *largest* at the smallest
n. On an all-strokes cel it is one enum discriminant and one blend-mode compare per element against a
1.55 ms blit, and the arithmetic says it should be invisible; this is the measurement that says it is.

**What this makes the next optimisation, if anyone wants one.** Nothing in the ink half is worth
touching - 3.2 us a dab is the same walk the whole layer uses and §11.2 has already established it is
linear and flat. The 2.5 ms is one 8 MB blit plus one 8 MB allocation per pen-up, and it exists
because `renderLocalContent` must hand back an immutable `UIImage`. A mutable standing bitmap stamped
in place would remove both, and would cost the memo its immutability - which is the same trade
[RENDER.md](RENDER.md) §3.8 makes carefully elsewhere, and is **not** proposed here: 3.4 ms a pen-up
is four frames' headroom at 60 Hz and nothing in §11.7 is waiting on it. Recorded so the next person
does not re-derive it.

### 11.10 The cross eraser: bounding a middle-of-list edit by the area it touched (2026-09-05)

The owner, on a build carrying everything from the previous session: *"right now when I draw a bunch
of brushstrokes and then use the cross eraser on them, I get a lagspike."* §11.8 made an **append**
incremental; every other edit still dropped the memo and re-walked the cel. TODO (41) is the rest of
it, and this is what it bought.

*"Cross eraser"* is `VectorEraserMode.cutToIntersection`, labelled **To Cross** — Mode 3, which
resolves and invalidates **once per touch sample**, so a 40-sample drag pays whatever one cut costs
forty times. Mode 2 (**Cut**) commits once at lift. Both now declare `VectorCanvas.Damage.region`
instead of `.everything`, and `repairableBase(quality:)` repairs that rectangle in the standing
picture rather than walking the list.

**Provenance.** MEASURED on an iPad Pro 13-inch M4 simulator, iOS 26.5, **Release**
(`ENABLE_TESTABILITY=YES`, which leaves `-O` on and only re-enables `@testable`), canvas 2048x1024,
the same 400 pt / 40-sample / size-18 fixture as the rest of §11 —
`StrokeDensityBench.testWhereACrossEraserDragSpendsItsTime`. **The before arm is the same commit with
`repairableBase` forced to return nil**, so the two arms differ in the feature and in nothing else:
not the compiler, not the brush chain, not the per-stroke transparency layer this session's other
work added. This Mac was at 84.4% idle for the before arm and 82.7% for the after arm, with one other
session's `xcodebuild` alive in both.

**The before arm reproduces §11.2's line, which is what says the harness is measuring the right
thing.** Its n = 1000 single-cut re-walk is 564.8 ms; times §11.2's measured 1.32 device ratio that
is **745 ms**, against §11.2's own iPad figure of **744.8 ms**. At n = 2000 it is 1142.9 x 1.32 =
1509 ms against 1489.4. So the "before" here is the same full re-walk this section has always
measured, reached by a different door.

**To Cross — a 40-sample drag across the densest part of the canvas.**

| n strokes | dabs before | dabs after | render total before | after | **worst single render** before | after | mean rectangle |
|---|---|---|---|---|---|---|---|
| 200 | 1,595,374 | **454,568** | 3.77 s | **0.73 s** | 137.3 ms | **40.8 ms** | 10.0% |
| 500 | 4,504,208 | **1,704,803** | 10.50 s | **2.80 s** | 283.2 ms | **96.8 ms** | 16.6% |
| 1000 | 9,040,998 | **3,932,797** | 22.36 s | **6.62 s** | 608.8 ms | **225.8 ms** | 21.6% |
| **2000** | 18,579,138 | **8,743,517** | 45.48 s | **15.20 s** | **1274.5 ms** | **463.2 ms** | 25.3% |

**Mode 2, a short flick through one or two lines — one cut, one render, which is the ordinary edit.**

| n strokes | dabs before | dabs after | render before | after | rectangle |
|---|---|---|---|---|---|
| 200 | 47,124 | **12,904** | 109.9 ms | **21.2 ms** | 10.8% |
| 500 | 117,567 | **62,579** | 296.5 ms | **109.8 ms** | 26.3% |
| 1000 | 235,284 | **147,020** | 564.8 ms | **259.2 ms** | 35.6% |
| 2000 | 470,664 | **293,664** | 1142.9 ms | **513.9 ms** | 35.6% |

**2.1-3.5x in dabs and 2.2-5.2x in wall clock — an order of magnitude less than §11.8's append got,
and the reason is in the rectangle column.** The append's prize was 105-832x because a new stroke's
damage is its own 236 dabs whatever the cel holds. A cut's damage is *the footprint of every stroke
it replaced*, and To Cross cuts **every** stroke whose centreline passes under the tip — so the
rectangle is the union of several 400 pt arcs' bounding boxes, and it **grows with density**: 10% of
the canvas at n = 200, 25% at n = 2000. The saving shrinks accordingly, and that is the guarantee
working rather than failing: cost scales with the area touched, and a denser drawing means a cut
touches more area. **Anyone quoting the 3.5x row should quote the 2.1x row beside it.**

**Half the repairs used to pay for two walks, and a margin removed it.** A cut piece re-anchors its
dab walk (`detachedPiece`), so its dabs sit at arc offsets its parent's did not and one near an end
reaches past the parent's measured union; the render then widens the clip by what escaped and goes
round again. MEASURED at **19 of 40 repairs**. `regionDamage(replacing:)` now declares the rectangle
widened by the largest brush diameter among the strokes it replaced — **not** a bound, since §12
stage 8 refuted a box derived from the brush, but a hint that makes the escape check pass first time.

| n = 2000, To Cross drag | widened | render total | worst single render | dabs |
|---|---|---|---|---|
| repair, no margin | 19 of 40 | 21.34 s | 938.1 ms | 8,414,133 |
| repair, with margin | **0 of 40** | **15.20 s** | **463.2 ms** | 8,743,517 (+2.6%) |

**The worst single render is the number this feature exists for** and it halved again for 2.6% more
dabs. INFERRED at §11.2's 1.32: on the owner's iPad 9 the worst render of a To Cross drag at 2,000
strokes goes from **~1.68 s to ~0.61 s**.

**What is left of the spike is now the *other* half, and it is on the main thread.** `resolveShare`
went from 13% to **31%** at n = 2000 because the render half fell and the resolve half did not:
worst single resolve **250.1 ms before, 236.7 ms after** (INFERRED ~330 and ~312 ms on the iPad). The
bench's own split says the spatial-index rebuild is only 8.2 ms of that at n = 2000, so the rest is
the per-sample intersection search `VectorLayer.swift` already flags as *"if a drag ever stutters in
a dense drawing, this loop is where to look first."* **It is now the largest single term the artist
can feel, because unlike the render it does not run on `StrokeCanvasView.renderQueue`.** That is the
next lever on this path and nothing here touches it.

**And the guarantee is no longer byte identity, which is a deliberate trade rather than a
regression.** A repair whose rectangle cuts a transparency layer disagrees with the full walk by one
or two units out of 255 on pixels along the rectangle's edge — MEASURED on an eraser's
`destinationOut` group, a `.multiply` run's isolation layer and a plain source-over stroke group, so
it is the truncation and not the blend mode. It does not accumulate: ten repairs in a row come out at
the same one unit as one. The margin above widens the rectangle and so puts more layers across that
edge, which is the cost side of the trade. `RegionRepairLogicTests` pins the bound three ways — a
bigger delta, a difference outside the rectangle, or more differing pixels than the rectangle has
boundary pixels — and still demands exact identity of the renders that are full walks.
