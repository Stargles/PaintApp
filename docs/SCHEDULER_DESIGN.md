# SCHEDULER_DESIGN — the scheduler and the memory manager, one page

Status: **S1 and S3a built (2026-11-25) — see "S1 as built" and "S3a as built" under §6; S2, S3b–S9 designed, not built.** [SCHEDULER.md](SCHEDULER.md) is the rules;
this page is what gets built, in what order, and how each step is proved. It answers TODO.md queue items
5, 6 and 9 (a)–(f). Figures are labelled MEASURED (with where), CODE (read off the source) or ESTIMATE.
The iPad 9 is the **minimum machine** (A13: 2 fast + 4 efficient cores, 3 GB, app limit 1,850 MiB); its
figures are floors and fixtures, never constants. "Picture" = canvas-sized bitmap, 95 MiB at 5000².

## 0. What the code says about the owner's complaints

| Symptom | Cause (CODE unless marked) |
|---|---|
| A step takes ~400 ms | **The step's own decode is held back by the touch that asked for it.** `FrameBaker.image(for:)` misses while flipping and calls `kick()`; `nextWork()` refuses while `InteractionGate.isClosed` — the finger down, plus 0.25 s — and looks again 0.25 s later. So 250–500 ms before the decode even starts. Two more: the top-up (`fillRingAhead`) runs only when **no frame in the scene is dirty**, so during a bake it waits for the whole scene; and the ring is `.cache` while stopped, so a bake's `waitForRoom(2 frames)` empties it. If the top-up has not landed by `frameStepSettleSeconds` (0.5 s), the read decodes **on main** (rule 2). The constants bracket his 400 ms; M1 (§9) confirms it on the trace. |
| "One step 2.2–2.4 s" (gate) | Not the step: 0.5 s settle + five layer renders **one after another** on `DeferredVectorRender.queue` (5 × 350–640 ms). The right frame can be up long before; the gate's probe times the settled state. |
| Layers arrive staggered, look different | Five hosts render and draw their windows through five independent `LatestWins`, each landing in its own main turn. The bake covers them only while the canvas is `.disengaged` **and** the baker can give the picture then; a refused or evicted read returns `bakedFramePicture`, which may be nil — then there is no cover. |
| Late edges on zoom-out | `CanvasPictureView`/`BakedFrameWindow` hold only the window's pixels; nothing lies under them. |
| Bake: seconds a frame | (1) 2-frame wait for room while the hosts' renders hold theirs; (2) a bake **refused part-way throws its walks away** (`.deferred`); (3) walks of the same cel repeat per frame because leaf memos are `.cache` and go first; (4) one frame at a time, three leaves at a time, whatever the cores. |
| Frames far from the playhead are orange again | `FrameBakeStore.defaultByteCeiling` is 512 MiB; Test1's files are ~25 MB, so **about 20 frames fit**. A real scene can never be fully baked. And the bake folder is emptied at every launch (RENDER.md §2.11), because the key is built from in-memory counters. |
| An Undo can wait on a bake | `VectorCanvas.rasterizeLock` is held through a whole walk; R1's repair of a cel queues behind R3's walk of it (up to 640 ms). |

## 1. Map — every heavy producer today

Cancel: **W** = waiting request only (`LatestWins`), **G** = pauses at gate checkpoints, **—** = runs to the end.

| Work | file:symbol | Queue, QoS | Size at 5000² | Class | Cancel | On main |
|---|---|---|---|---|---|---|
| Frame bake | `FrameBaker.nextWork` | own serial, utility | 2 pictures + leaves | R3 | W G | O(layers) mint ×2 |
| Baked-frame read | `FrameBaker.image(for:)`, `fillRingAhead` | **same queue as the bake** | 95 MiB | R1 | W | sync decode after settle |
| Baked frame on screen | `CanvasView.showBakedFrame` | own serial, userInit. | window | R0 feed | W | `presentFirst` draws on main |
| Layer picture | `StrokeCanvasView.startVectorRender` | `DeferredVectorRender.queue`, serial, userInit. | 1–2 pictures | R1 | superseded only before it starts | landing |
| Layer/onion window draw | `CanvasPictureView` | concurrent, userInit. | window | R0 feed | W | — |
| Live ink, live eraser | `StrokeScratch.renderQueue` | serial | window | R0/R1 | W | `settleCelContent()` renders; live dab stamping |
| Sandwich halves, eyedropper | `CanvasView.sandwichQueue` | serial, userInit. | 2–3 pictures | R2 | W | O(layers) mint |
| Onion skin | `CanvasView.onionQueue` | serial | reduced | R2 | W | — |
| Thumbnails | `thumbnailRegenQueue`, `thumbnailBackfillQueue` | utility | 1 picture flatten | R2 | task only | install |
| Fill | `CanvasManager.fillQueue` + `MetalFillEngine` | serial, **userInteractive** | up to picture + reference | R1 | W | `fillQueue.sync {}` (`+Fill:243`); GPU waits ×5 |
| Move lift | `CanvasView` → `renderIsolated` | **main** | ≤ 1 picture | R1 | — | the render itself |
| Liquify | `CanvasManager.liquifyCommits` | serial, userInit. | window field | R1 | W | — |
| Shape / text / brush previews | `ShapeOverlayView`, `TextOverlayView`, `StrokeSettingsPanel` | 2 queues + a Task | small–window | R1 | W | landing |
| Canvas edits (flip, resize, pixels) | `prepareCanvasUpdate` | `canvasPixels`, userInit. | pictures | R1 | generation | landing |
| Value fill | `LayerFillView.fillDrawQueue` | serial | window | R2 | W | — |
| Undo picture | edit → `startVectorRender` repair | shares the layer queue | copy of the picture + damage | R1 | as layer picture | model edit |
| Stream | `ScreenStreamClient`, `H264StreamDecoder`, `onTopStreamQueue` | 3 queues, userInit. | 1080p + window | R2 | drops | ≤ 1 tick |
| Export | `FrameExportSession.workQueue` | serial, userInit. | 1–2 pictures | R3 | cancel flag | — |
| Save, checkpoint | `ProjectStore.saveQueue` | serial, userInit. | per cel PNG | R3 | — | `serializingPackageMutation` can `.sync` |
| Project load | `ProjectStore.loadQueue` | concurrent, userInit. | per cel | R1 (he waits) | — | install |
| Raster loads | `RasterSource` `DispatchGroup` waits | caller's | per cel | caller's | — | can wait |
| Recorder, crash ring | `ActionRecorder`, `UncleanExit` | utility | small | R3 | — | — |
| GPU compositor, effects, warp | `MetalCompositor`, `MetalEffects`, `ImageWarp` | caller waits (`waitUntilCompleted`) | strips | caller's | — | if caller is main |
| Fan-out | `PixelOps.parallelMap` (`concurrentPerform`, all cores) | caller's | n × job | caller's | — | — |

Nothing above sees the touch flag except the bake; nothing can be stopped mid-walk; no two know of each other.

## 2. Core

Four small files in `Engine/Scheduling/`, Swift standard library + Foundation value types only — no
UIKit, Dispatch, Metal or `ProcessInfo`. They compile for Android/Windows with a different executor.

```swift
enum JobClass: Int { case answer, soon, later }             // R1, R2, R3. R0 is the main thread and is never a job.
struct JobKey: Hashable { let owner: String; let subject: AnyHashable }   // the latest-wins identity
final class CancelToken: Sendable { func cancel(); var isCancelled: Bool }
struct Need { var bytes: Int                                // the PEAK, granted whole before start
              var tileBytes = 0, maxTiles = 1               // bytes per extra parallel tile
              var gpu = false, disk = false }
struct Job<R> { key, jobClass, name, need, deadline: Duration?, visible: Bool
                work: (JobContext) throws -> R, land: @MainActor (R) -> Void }
struct JobContext { let token: CancelToken
    func checkpoint() throws                                // cancelled → throws; must pause → parks here
    func tiles<T>(_ n: Int, _ body: (Int, inout Workspace) throws -> T) throws -> [T]
    func workspace(_ bytes: Int) -> Workspace               // drawn from the job's own grant, never the pool
    func promote(to: JobClass) }                            // a waited-for R2 becomes R1
final class Scheduler { func submit(_:) -> JobHandle; func cancel(key:); func touches(_ count: Int)
                        func request(key:, mint: @MainActor () -> Job?) }  // LatestWins' contract, kept
protocol Executor { func start(_ lane: Lane, _ body: @escaping () -> Void); func main(_ body: …); var now: Instant { get } }
protocol Machine  { var fastCores: Int; var efficientCores: Int; var hasGPU: Bool; var appLimitBytes: Int
                    var availableBytes: Int?; var freeDiskBytes: Int; var heat: Heat; var refreshHz: Double }
```

- **One seam.** `Platform/AppleExecutor.swift` is the only file that may spell `DispatchQueue(`,
  `concurrentPerform` or `Thread`; `Platform/AppleMachine.swift` the only one reading `sysctl`
  (`hw.perflevel0/1.physicalcpu`), `os_proc_available_memory`, `thermalState`, disk space. A lint
  (`tools/check-scheduling-seam.py`) starts with today's list as its allowlist and only shrinks.
- **Lanes and cores** (P fast, E efficient, read from `Machine`; one fast core is never given away while a
  touch is down — it is the pencil's, the main thread's and the window server's):
  | state | R1 | R2 | R3 |
  |---|---|---|---|
  | touch down, or < 250 ms after | up to max(1, P−1) fast + ⌈E/2⌉ efficient tiles | 1 worker, `visible` jobs only | parked at checkpoint |
  | idle, R1 running | same | 1 | 1 efficient |
  | idle, no R1 | — | 2 | all but one core, as tiles |
  | hot (thermal serious) or low power | same | 1 | 1 efficient |
  Minimum machine: R1 = 1 fast + 2 efficient tiles; an idle bake = 1 fast + 4 efficient. One R1 *job* runs at a
  time, fanned out; a second, different-key R1 job waits only for a tile slot. Tiles are claimed one at a
  time, so efficient cores simply claim fewer; no static split to balance.
- **QoS mapping** (Apple): R1 `.userInitiated`, R2 `.utility`, R3 `.utility` idle / `.background` while a touch is
  down or hot. `.userInteractive` belongs to main alone (fill loses it). The compute pools are ours, not
  Swift concurrency's cooperative pool, which blocking compute starves.
- **Parallelism = min(cores, memory)**: `tiles` takes as many workers as slots *and* `need.tileBytes` allow at
  admission. Today's `min(3, free/leaf)` in `streamFlatStack` and `parallelMap`'s all-cores are deleted into it.
- **GPU**: used for effects, fill, warp and any Metal composite, as now. A job marked `gpu` submits and returns its
  slot; the command buffer's completion resumes it (no core sits in `waitUntilCompleted`). One R1 and
  one later command buffer in flight; later work is cut into buffers ≤ 8 ms so a touch's draw is not queued behind
  it. Flat stacks stay on CPU: the bake's cost is the vector walk, not the blend (PERFORMANCE.md §11).
- **Cancel and checkpoints**: `checkpoint()` at least every 10 ms of fast-core work: between elements and every
  256 dabs in `VectorCanvas.walk`, between tiles elsewhere. R1 cancel is thus ≤ 10 ms; R3 park ≤ 50 ms on an E core.
- **No lock across a walk.** `rasterizeLock` goes: "two callers, one picture" becomes *same `JobKey`* — the second
  request joins the running job and promotes it. This ends R1-behind-R3 on one cel.
- **Deadlines**: R1 carries 100 ms. Missing it never blocks — it logs `late` with waiting/running split (rule 8)
  and the last complete picture stays. R2 past 500 ms is dropped if its key was re-requested.
- **Testing**: `VirtualExecutor` (manual clock, scripted durations per tile) drives every rule as a logic test on
  any core count — 1+0, 2+4, 4+4, 8 — and a 2,000-step random storm asserts: no R3 tile starts with a touch
  down; at most one landing per key per request; a cancelled job never lands; granted bytes ≤ budget always;
  every job eventually lands, is cancelled or is refused.

### 2.1 Presentation — the screen never mixes old and new (structural)

`CanvasPresenter` becomes the **only** owner of what the canvas shows: one `Presented` value, replaced whole.

```swift
enum Presented { case whole(Picture)                        // one flattened frame
                 case cut(below: Picture?, hosts: [HostPicture], above: Picture?) }  // LivePairCut, unchanged
```
A new value is *prepared* off main: each part draws its window into its own back surface. When **every** part is
ready and all carry one `(frame, revisions, window)` stamp, one main turn swaps all `layer.contents` in one
`CATransaction` and retires covered live ink in the same turn. A part that fails or is superseded drops the whole
set; the screen keeps what it has. Nothing else may set contents, so "mixed" has no code path. Replaces:
per-host landings, `isAwaitingFirstPicture`, `coverTheHostsWithTheBakeWhileTheyRender`, the held frame,
`frameStepSettleSeconds`, `presentFirst`'s draw on main. It is not a diagnosis of the flicker when laying several
strokes — that is re-tested on the build (TODO item 7) — but it makes that class of flicker inexpressible.

## 3. Memory manager — `MemoryBudget` grown, not replaced

Kept: one number (0.48 of the app's limit, 888 MiB on the minimum machine), entries, grants, the device
valve, pressure trims. Added: what an entry declares, reservation, tiers, arbitration. Deleted at the end:
`Priority` as three hand-set levels, `waitForRoom`, `currentLane` in thread dictionaries, per-cache shares
(`frameRingShareDivisor`, `UndoBudget.physical/16`, `defaultByteCeiling`, `CompositorBudget.textureBudgetBytes`
as a *budget* — it stays as a strip height).

**What an entry declares (item 9 (a)) — mechanism central, policy per feature:**

```swift
struct EntryFacts { owner: Feature; key: ContentKey; bytes: Int
    comesBack: .rebuild(ms) | .disk(ms) | .never             // measured by the manager: last real cost, not a guess
    nextUse: .now | .soon(rank: Int) | .unlikely             // rank 0 = the next frame / adjacent layer
    standIns: [StandIn] }                                    // .half, .quarter, .merged(into: key)
protocol FeaturePolicy { var floorBytes: Int { get }         // what it may always keep
    func nextUse(of: ContentKey, _ view: ViewState) -> NextUse   // playhead, direction, active layer, window
    func accepts(_ s: StandIn, for: ContentKey) -> Bool
    func encode(_ key: ContentKey) -> Encoder?               // how it spills; nil = never spilled
    func restored(_ key: ContentKey, _ tier: Tier) }         // "your picture is back" — never "free yours now"
```
A feature answers questions; only the manager decides *when*. No feature frees, spills or loads on its own;
the manager deletes the bytes, so a hook that forgets cannot leak.

**Reservation (b) — real time first.** Two pots nothing else may take: **R0** = the on-screen window surfaces and
the live stroke's window (derived: ≤ 4 windows; 53 MiB at 2160×1620) and **R1** = one picture plus a
half-picture scratch (143 MiB at 5000², capped at 1/5 of the budget). R2/R3 and predictions draw only from
what is left. R0/R1 never read disk: what R1 may need next (the active layer, its neighbours' inputs, the shown
frame) is memory by policy, and an R1 job that finds it on disk does not wait — the last complete picture
stays and the load runs as a promoted R2 job (counted: `r1DiskWaits` must be 0).

**A job asks once.** `Need.bytes` is the peak; admission grants it whole or not at all; sub-allocations draw from
that grant (`workspace`), so nothing is refused half-way and **no job holding memory ever waits for more**.
R2/R3 that do not fit stay queued holding nothing and are re-tried when bytes are returned (an event, not a
0.05 s poll). An R1 that cannot fit even after eviction says so through the existing notices.

**Tiers**: memory → **disk** (one `PictureStore`: tiled LZ4, 512×512 tiles, SHA-256 content key) → **rebuild**.
- *Evict* drops the bytes if a file or rebuild exists; *spill* (R3) writes first. Spill only when
  `rebuildMs > 2 × reloadMs` **and** it compressed below 60%. A vector layer (350–640 ms to walk on device,
  MEASURED; 25–115 ms to reload one-core, from PERFORMANCE §10.2 scaled ×1.49–5.96, ESTIMATE) always passes; a
  thumbnail never does. `.never` entries (raster undo) must spill before they may be evicted.
- *Disk limit (d)*: one number for bakes + spill + undo: `min(4 GiB, 10% of free disk)`, always leaving 2 GiB
  free (below that: no spill, bakes near the playhead only). Read at launch and when a write fails.
- *Write rate*: a token bucket at ¼ of the write speed measured on the first writes (floor 20 MiB/s), shared by
  bakes and spill. Writes are R3 and stop under a touch.
- Rebuildable files live in Caches; `.never` files in an excluded-from-backup session folder, emptied on close.

**Where the OS helps, and where it does not.** (Stated plainly; nothing here relies on the unsure ones.)
| Mechanism | Verdict |
|---|---|
| Untouched pages of a zeroed (`calloc`) buffer | **Helps.** `PixelOps.drawImage` already callocs and never clears: blank rows are never resident, so we *over*-charge sparse layers. M6 measures by how much; if ≥ 25%, charge the touched pages (`mincore`) after a render. |
| `mmap` of a clean file | Not in the footprint, so good for **compressed** files read by R2/R3 (the store's reads become mapped). **Not** for pixels R0/R1 touch: a page fault is a hidden disk wait, and 95 MiB uncompressed files would quadruple the writes. |
| Purgeable memory / `NSCache` | Not used: the system drops in its own order, invisible to our floors, and a purged picture is found at draw time — on the path that may not wait. |
| Memory compression | Not relied on. Whether a compressed page still counts in full against the app's jetsam limit is disputed in our own notes (PERFORMANCE.md, the residency item's unmeasured terms, says compressed size; XNU's ledger reads as full page size). It can only slow a touch that faults a page back in. |
| App killed at its own limit regardless of system free memory | The reason the manager exists: no OS mechanism trades one of our pictures for another. |

**Arbitration (c)** — one order, whenever room is needed:
1. Who is asking: R1 may evict `.soon`/`.unlikely`; R2 only `.unlikely` and `.soon` of a lower rank than itself;
   R3 only `.unlikely`. `.now` (on screen) is never evicted.
2. Before evicting, take an accepted stand-in (a half-size frame frees ¾ and still draws).
3. Victims by `nextUse`, then **cost to get back per byte freed, cheapest first**, then least recently used.
4. **Floors**: each feature keeps `floorBytes` against everyone but R1 (undo 8 MiB and its newest step; ring 1 half
   frame; stream 1 frame; thumbnails 4 MiB; layers 0 — they are `.now` or nothing). Floors sum to ≤ 10%.
5. **Anti-thrash**: a loaded entry stays ≥ 2 s unless R1 needs the bytes; evicted and wanted again within 2 s counts
   as a thrash and doubles that entry's stay (to 30 s); a file-backed entry is dropped, not re-written; a prediction
   never evicts another prediction of equal or better rank; predictions stop when thrashes > 2 in 10 s.

**Predictive loading** (R2, only from free room): stopped — frames ±1, then 2 more in the last step's direction,
then the adjacent layers' pictures; playing — the next second, half size at fit zoom; scrubbing — nothing but the
frame under the finger. A touch on the canvas cancels it.

### 3.1 Layouts

**Layer pictures.** Today 5 × 95 = 477 MiB on screen, growing with the layer count. New: `below` (everything under
the active layer, merged), the active layer, `above` (merged) — **≤ 286 MiB at any layer count** — using the existing
`SandwichRecipe`/`LivePairCut` composites for every document; the flat row of per-layer hosts is deleted. Where
something above blends or grades, the existing `.overHost` cut: one merged picture + active. A live stream or
float widens the middle run as `liveHostRun` says: one picture per layer in it. The other layers' own pictures are
`.soon` (the two neighbours) or on disk.

Pictures become **app-private and repaired in place**: since `d72eb69f` the render server only ever gets window
surfaces, so nothing outside holds a picture. An edit renders its damage into a damage-sized scratch, then copies it
in under the picture's short lock (≤ 2 ms) and stamps the revision. Reads mint a fresh `CGImage` wrapper each time, so
CoreGraphics cannot serve a stale copy; a bake reads in ≤ 10 ms bands and is cancelled if the revision moves.
This deletes the 95 MiB copy per landed edit and the copy per Undo. Not chosen: tiling the in-memory picture (seams
under fractional scaling; every reader rewritten) and copy-on-write pages (Apple-only; double-counted footprint risk).

| Event | What happens | Latency on the minimum machine (ESTIMATE) |
|---|---|---|
| Stroke lands | damage repaired in place; `below`/`above` untouched | one damage walk; ≤ 100 ms |
| Layer switch, neighbour | screen unchanged at once; R2 makes the new cut: `below ∪ old`, rest merged from memory | 0 visible; cut ≈ 60–120 ms |
| Layer switch, far | same, leaves loaded from disk (parallel) | 0 visible; cut ≈ 150–300 ms |
| Pen down before the cut is ready | ink draws at once over the last complete picture; swaps in at its true depth when the cut lands; the cut is promoted to R1 | ink 0; depth ≤ 300 ms |
| Undo/Redo on the active layer | the step's kept pixels are copied back (below); no walk | ≤ 50 ms + window draw |
| Undo elsewhere (other frame/layer) | model at once; whole picture held until the new set is complete | as a frame step / layer switch |
| Move, Liquify, lasso float | the active leaf + existing `aroundRuns` bands; hole repaired in place; extra ≤ 1 picture from the R1 pot | lift ≤ 100 ms off main |
| Pan / zoom | window redraw from resident pictures at display rate; half-size `whole` sits under the window | revealed edges 0 (soft), sharp ≤ 50 ms |
| Multi-layer group/transform edit | existing bands, made from leaves (disk or neighbours) | ≤ 300 ms, held picture until then |

**Baked frames.** File v2: the frame at full size **and** half size (box filter; quarter when the canvas exceeds
3× the window), each in 512-px tiles, each tile its own LZ4 block, index in the header. Display reads the
smallest level at least as fine as the screen, and only tiles the window needs. At fit zoom on 5000² that is the half
level: 24 MiB, not 95. So the ring keeps 8 frames in the bytes that hold 2 today. Half levels are kept for the whole
scene; full levels for the nearest the disk limit allows. (Not "rendering below the knob", RENDER §2.12: the
screen cannot show the difference at that zoom, and zooming in loads the full tiles.) `whole` at half size of the shown
frame stays `.now` — it is the picture under the window (§4, edges).

**Undo.** `UndoHistory` becomes a feature: its steps are entries. An edit's replaced pixels (its damage rectangle, LZ4) are
kept with the step, keyed before-revision → after-revision. For a **vector** layer this is a cache (a chain mismatch or
eviction falls back to the repair walk); for **raster** it *is* the step, priced by damage instead of 190.7 MB a step,
`.never`, spilled oldest first instead of dropped. The 192 MiB cap goes; depth is bounded by disk and the floor.
The unattributed ~250 MiB at Undo: **M2 before S3** (§9).

**Stream.** One decoded frame + two window surfaces, R2, fixed at connect and charged; no entry until measured (M7).
Queue depth 1, late frames dropped. Nothing else about it changes in these merges.

| Minimum machine, Test1 shape, idle | today (MEASURED 667) | design (ESTIMATE) |
|---|---|---|
| layer pictures | 477 | 286 |
| frame/halves/ring/other | ~190 | 72 (3 half frames) + M2's remainder |
| undo kept pixels | outside | 64 |
| R0 + R1 reserve | 0 | 196 |
| a bake's working set | +191 (two pictures) | +96 (§5) |
| **total of 888** | 858 + waits | **≈ 714** |

## 4. Frame step — tap to screen

Budgets are for the minimum machine; every line is a named span, and the counts are what the tests assert.

| # | Step | Where | Budget |
|---|---|---|---|
| 1 | tap → `currentFrame`, one editor pass | main | ≤ 4 ms canvas work (the SwiftUI pass itself is measured, M1) |
| 2 | `scheduler.request(key: .frame)` — R1, cancels the last one; not held by the touch flag, not behind the bake | — | 0 |
| 3a | **in memory** (±1 predicted): wrap | R1 | < 1 ms |
| 3b | **on disk**: read + decode the level's visible tiles, parallel | R1 | 10–30 ms half level at fit (dense, 3 tiles wide; ESTIMATE from §10.2: 19 ms per 2048² painted, one core) |
| 4 | draw into the back surface (one window) | R1 | 10–20 ms (M5) |
| 5 | swap `Presented.whole`, one transaction | main | < 1 ms, next vsync |
| | **tap → whole frame** | | **memory ≤ 50 ms, disk ≤ 85 ms** — firm R1 is 100 |
| 6 | still for 150 ms: R2 makes the cut; all parts ready → one swap | R2 | 0.2–0.6 s, **invisible** if M3 holds |

- **The whole frame at once.** Step 5 puts one flattened picture up; step 6 replaces it in one turn or not at all. The
  active layer is never shown ahead of the rest. M3 measures whole-vs-cut at the same window; if the
  difference exceeds 2/255 on more than 0.1% of pixels, the cut's parts are drawn from half levels too (+25%
  memory on three pictures), so both go through one filter.
- **Rapid stepping**: one key, so a newer step cancels the older read at the next tile (≤ 5 ms); no cuts, no predictions
  beyond ±1 while steps come < 150 ms apart; each tap still presents something if its read finished.
- **Unbaked**: the last complete picture stays; the frame jumps to the head as **R1** (not a bake: built for the screen,
  then handed to the bake writer so it is never built twice). 5 walks, 350–640 ms each, across tiles:
  ~0.8–1.5 s on the minimum machine (ESTIMATE). Above 100 ms — hence question Q1.
- **Pen down during 3–6**: `promote(.answer)` on the cut; ink as in §3.1.
- **Playing** uses the same path: reads are R1 one frame ahead of the clock; predictions fill a second ahead.
- **Edges**: the half-size `whole` is drawn in a canvas-placed layer under the window surfaces (24 MiB of pixels, one
  reduced IOSurface handed to the server: ≤ 1024² = 4 MiB). Pan and zoom move it in the same
  transaction as the canvas, so revealed areas are never blank.

## 5. Bake throughput

**Why it waits today**: `waitForRoom(2 × 95 MiB)` against 667 held leaves 221 of 888 — room for a bake only when no host
render is in flight (each holds 1–2 pictures), and a refusal part-way repeats the walks. **How it ends**: idle holds
fall to ~400–450; the bake asks for **bands**, not frames: 5000×1024 rows; each core needs a leaf band + destination
band + encode buffer ≈ 60 MiB, so 96 MiB runs one band always and more when free; nothing is granted part-way.

1. **Never walk a cel twice.** A walked leaf goes to `PictureStore` (keyed by content, not frame). The frame on screen
   costs no walk (its pictures are there). **Count: walks = distinct cel revisions, not frames × layers.**
2. **Reuse held runs.** Order bakes by cel, not only distance: frames that share a bottom or top run of layers reuse
   one merged picture. Backgrounds and holds then cost one merge a run, not one a frame. `BakeQueue`'s bands stay:
   playhead first, direction, outward; reordering happens only inside a band.
3. **Use every core**: tiles of one frame across cores while idle (1 fast + 4 efficient on the minimum machine);
   two frames at once only when memory allows both bands. Stops within 50 ms of a touch, keeping finished bands —
   **a pause or cancel no longer throws work away**.
4. **Pay once for the levels**: half/quarter are box-filtered from each band as it leaves the composite.
5. **Keep more**: the disk limit (§3) holds half levels for a whole scene; see Q2 for keeping them between launches.

Expected, Test1 shape, minimum machine (ESTIMATE): frame with no new cel ≈ 0.15–0.3 s; frame of five new cels
≈ 0.8–1.3 s (walk-bound: 1.75–3.2 core-seconds over ~3 effective cores); simulator counts are the gate.
**The floor is the vector walk.** If M4 shows placed images dominate it, cache their window-scaled decode; if dabs do,
GPU stamping is a separate future project, not promised here.

## 6. Migration — small merges, each shippable and gated

Every merge: the fast tier Debug + Release, its own cold-start XCUITest on the artist's path, `tools/playcheck.sh`
GREEN (app ≤ 1,165 MiB, `backboardd` ≤ 450 MiB) and the counts below printed by the gate's trace. Simulator times
are compared **before vs after on the same simulator**, never against device figures. "Delete" is whole: code,
tests of the old path, doc text.

| # | Merge | Touches | Deletes | Proof (artist's path) | Gate numbers | Size, model, risk |
|---|---|---|---|---|---|---|
| **S1** | **Frame steps: core + R1 frame reads + presenter** | new `Engine/Scheduling/*`, `Platform/Apple*`; `FrameBaker` (read path), `DecodedFrameRing`, `CanvasView` baked-frame + sandwich presentation, `CanvasPictureView`, `ModifierHoldHost`, `CanvasManager` step | `InteractionGate` (becomes the scheduler's touch flag), `frameStepSettleSeconds` + `frameStepIsSettling` (→ "steps stopped 150 ms"), the main-thread decode in `image(for:)`, `fillRingAhead`'s place behind the bake, `coverTheHostsWithTheBakeWhileTheyRender`, `bakedFrameCoveringTheHosts`, `isAwaitingFirstPicture`, held-frame surface, `presentFirst`'s main draw | `FrameStepUITests` from a new document: two layers × three frames drawn, baked; step ±1 ×12 quickly then slowly; screen probe each step | `storeDecode` on main **0**; step reads held by touch **0**; presented sets per settled step **≤ 2** (whole, cut); frames with mixed rows **0**; gate "one step to a whole frame" from 2.23–2.38 s to **≤ 0.3 s** (probe moves to the app's `presented:` census field, ms) | ~1,300 lines; **Opus**; medium: presentation ordering vs live-ink retirement |
| **S2** | Bake file v2 (tiles + levels), window reads, picture under the window, disk limit | `FrameBakeStore`, `DecodedFrameRing`, `BakedFrameWindow`, `FrameExportSession` reads full level, `AppleMachine` disk | v1 format (bump `formatVersion`, Caches only — no repair needed), `frameRingByteBudget`'s ~4900² cliff, `frameRingShareDivisor`, `defaultByteCeiling` | `ZoomEdgesUITests`: zoom in, pinch out, probe the revealed edge in the first frame; export round trip | revealed-edge blank frames **0**; ring frames held at 5000² **≥ 6** (was 2); decoded bytes per step at fit **≤ 25 MiB** (was 95) | ~800; **Sonnet** with this page; low |
| **S3a** | R1 queues onto the scheduler | `DeferredVectorRender`, `StrokeScratch`, `prepareCanvasUpdate`, Liquify, fill (`fillQueue`, its `.sync`), text/shape previews | 6 `DispatchQueue`s, `fillQueue.sync {}`, `Pacing` (its reason — a server copy per landing — ended with `d72eb69f`; re-measure the undo storm's window draws first) | existing stroke/fill/Liquify UI tests + an Undo storm | R1 `late` **0** on the gate; main spans unchanged or lower | ~700; **Sonnet**; low |
| **S3b** | In-place repair, kept undo pixels, cancellable walks, no lock across a walk | `VectorCanvas` render/walk, `StrokeCanvasView` landing, `UndoHistory`, raster undo | `rasterizeLock`; the copy per landed edit and per Undo; `renderIsolated` on main (Move lift) | `UndoLatencyUITests`: cold start, five strokes, Undo ×5 fast then Redo ×5, probe each | Undo phase peak **≤ the other phases' + 20 MiB** (was +90); per-Undo picture copies **0**; walks per Undo **0** while kept pixels hold; R1 waits behind R3 **0** | ~1,200; **Opus**; high — needs **M2** first |
| **S4** | Memory manager (stage 3b) | `MemoryBudget` → facts, policies, reservation, arbitration, `PictureStore` spill on S2's codec, predictions; features: layer memos, flatten memo, ring, `RasterResidency`, undo | `Priority`, `waitForRoom`, `currentLane`/`withLane`, `UndoBudget` cap, per-cache shares | `LayerSwitchUITests`: 5 layers, switch far and near, draw at once; logic storms on `VirtualExecutor` | `r1DiskWaits` **0**; spill/load spans on main **0**; thrash events **0** on the playcheck; hit rates printed per feature | ~1,400; **Opus**; medium |
| **S5** | Two merged pictures, always | `CanvasView` presentation, `RenderRequest.sandwichEngagesOnCanvas`, layer hosts | the flat row (each layer drawing itself at rest), `.shown` per-host pins, `liveHostsBesidesTheActive` special cases that the cut covers | 8-layer fixture: enter, draw on layer 2 then 7, Undo, Move | idle layer pictures **≤ 3** at any layer count; app idle peak with **8** layers ≤ the 5-layer peak + 10 MiB | ~1,000; **Opus**; high (every live path) |
| **S6** | Bake throughput | `FrameBaker`, `StripedComposite`, `BakeQueue` (order within bands), `PixelOps.parallelMap` → `tiles` | `waitForRoom` in the bake, `Outcome.deferred`'s discard, `min(3, …)` batch | playcheck's bake phase | walks **=** distinct cel revisions; bake deferrals **0**; scene bake ≥ **2×** faster than S5 on the same simulator | ~800; **Opus** for bands, **Sonnet** for reuse; medium |
| **S7** | R2/R3 guests | thumbnails, onion, sandwich, value fill, eyedropper, export, save, load, recorder, crash ring | their queues; `serializingPackageMutation`'s `.sync` from main; seam lint allowlist → **empty** | existing UI tests of each + a save during a stroke | seam lint **0 exceptions**; unattributed main time **0** | 3 × ~500; **Sonnet**; low |
| **S8** | Stream as a guest | after **M7** | its 3 queues | `StreamLive*` suites, stream on vs off | stroke spans with stream on within 5% of off | ~400; **Sonnet**; low |
| **S9** | Rule 9 on the device | `DeviceStressUITests` burst + trace assertions | — | device burst when the iPad is already unlocked | max main pass, R1 p95 ≤ 100 ms, the counts above | ~300; **Sonnet** |

S1 ships the owner's most visible fix on its own; S2 makes the step cheap at any zoom. S3b waits for M2; S5 waits for S4.

### S1 as built (2026-11-25)

**M1, the cause as measured** (iPad 9 simulator, Test1 shape, `FrameStepUITests` on the old code, app clock via
`step:` / `FrameStepCensus`): the step's decode began **267–268 ms after every slow step** — the touch flag's
250 ms settle plus a frame, §0's cause exactly — and the whole frame was up at **324–347 ms**; **8 main-thread
decodes in 8 steps**. The owner's recording of a ruler scrub on a baked 2048×1024 scene read **0 ring hits in
110 flips**: with a pencil down the whole scrub, every read waited. After S1, same simulator and test: **39–94 ms**
at 5000², **18–27 ms** on the 2048×1024 scene (one or two display frames), 0 main-thread decodes, 0 mixed
samples. The playcheck's screen probe still reads ~2.2 s: it polls through `XCTNSPredicateExpectation` (about a
second) and element screenshots, so it timed the probe; the gate now prints the app clock beside it.

**Built:** `Engine/Scheduling/` (`JobClass`, `JobKey`, `CancelToken`, `Job`, `JobContext.checkpoint`, `TouchFlag`,
`Executor`, `Machine`, `LanePolicy`, `Scheduler`) and `Platform/AppleExecutor.swift`, `AppleMachine.swift`;
`tools/check-scheduling-seam.py` with today's 18-file allowlist. Not yet: `Need`/admission (S4), `tiles` and
`workspace` (S6), `promote` and `request(key:mint:)` (S3a) — each lands with its first user. On it in S1: the
frame read (R1, `FrameBaker.requestRead`, never held by the touch, never on main; a ring-refused answer is kept
beside the ring) and the ring top-up (R2, `FrameBaker.topUpRing`, its own lane; stopped it also holds the frame
behind the playhead). The bake stays on its own worker until S6 and parks on the scheduler's touch flag.

**Presenter, as built:** not §2.1's `Presented` enum — the hosts still draw themselves — but its rule.
`CanvasPresenter` holds; each host's `WindowSurfaceView` parks its finished draw instead of swapping; a set goes up
in one `CATransaction` when complete (`CanvasView.Coordinator.settlePresentation`: the bake shows this frame, or
every visible host is ready, then the bake comes down with them). A step holds; the hosts taking over from the
bake hold; a stroke releases at once. Deleted: `InteractionGate`, `coverTheHostsWithTheBakeWhileTheyRender`,
`bakedFrameCoveringTheHosts`, `isAwaitingFirstPicture`, the canvas's `presentFirst` draw, the main-thread decode in
`image(for:)`, `fillRingAhead` behind the bake. `frameStepSettleSeconds` stays, at **0.15 s** (was 0.5): it now
only spares a burst renders nobody sees. Not replaced in S1: the held frame of a slider hold (TODO (179)),
`ShapeOverlayView`'s own `presentFirst`.

### S3a as built (2026-11-25)

**What moved onto the scheduler** (all R1, `.userInitiated`): the layer picture (`StrokeCanvasView.vectorRenders`) and
the held-edit and derivation surfaces' draws, `StrokeScratch`'s window picture, `prepareCanvasUpdate`, Liquify's
picture, the fill lane (`CanvasManager.fillWork`; the gesture's renders are a latest-wins lane of it), and the shape
and text previews. **Deleted:** `DeferredVectorRender.queue`, `StrokeScratch.renderQueue`, the `canvasPixels` and
`liquify` queues, `fillQueue`, `ShapeOverlayView.previewQueue`, `TextOverlayView.glyphQueue` (seven, not six), and
`DeferredVectorRender.Pacing` with its host timer. The seam lint's allowlist shrank by five files (18 → 13).

**Added to the core, each with its first user:** `Job.group` (jobs of one group run one at a time, in order — what a
shared serial queue gave: the fill session's state, two canvas-sized pictures never held at once; S4's admission by
bytes replaces it); `LatestWins(scheduler:key:…)` — §2's `request(key:mint:)`, kept as `LatestWins` because the
producers not yet moved (FrameBaker, sandwich, onion: S2/S7) still use its queue init; `Scheduler.waitUntilIdle(group:)`;
`Stats.lateByName`. **Not added:** `promote` — nothing in S3a asks for it.

**Deviation from §2: the R1 lane is a pool, not one job.** `LanePolicy` gives R1 `max(1, P−1) + ⌈E/2⌉` slots (3 on the
iPad 9), one per untiled job. One slot would have queued a live eraser's picture behind an Undo's 500 ms layer render,
which separate queues never did; the slots become tile counts in S6.

**Pacing, measured then deleted.** Undo storm (`RapidUndoSurfaceUITests`, 20 undos, 5000² × 5 layers, same simulator):
whole-cel rasterizes **21 → 18**, window draws **21 → 18**, the playcheck's `backboardd` peak **171 → 103 MiB** over the
run (limit 450; 44 MiB at the undo phase both times). Pacing's reason (a server copy per landing) is gone — the
census's `handed` reads 0 even before — and the latest-wins lane already bounds landings to one per render.

**Gate (iPad 9 sim, before → after):** playcheck GREEN both; app peak 1,116 → 1,126 MiB (limit 1,165), step to a whole
frame 106 → 47 ms, scene bake 20.1 → 1.1 s (bake phase is S1/S2's, noise here). **R1 `late` is 37, not 0:** 36 are
`layer picture` (a whole-cel render at 5000² is 350–640 ms; only S3b's in-place repair and cancellable walks bring it
under 100 ms), 1 `frame read`; stroke, eraser, fill, Liquify, text and shape answers are 0. The trace now prints
`r1late` by name and `draws:` (window pictures presented) beside the memory phases.

**The one wait left on main:** `commitInteractiveFill` still waits (`waitForFillWork`) when a second edit arrives before
the first fill's first render exists, because `beginCanvasEdit` must read a canvas the fill is already part of. It is
`fillQueue.sync {}` renamed, not removed: removing it makes the edit chokepoint asynchronous (owner ruling: a tap
during a still-rendering fill is either held until the fill lands, or ignored).

## 7. Owner rulings (Nov 25)

- **Q1 — a never-drawn frame:** keep showing the previous frame until the new one is whole. No soft-first.
- **Q2 — bakes between launches:** a Settings option to keep them, **default off**. When on, they are stored
  in the scene's own folder (they travel with the canvas), inside the disk limit; when off, emptied at launch
  as today. S2 builds it.

## 8. Changes to SCHEDULER.md (same branch)

Status updated; R1 names the frame a step asks for; rule 3 says reads of the shown frame are R1 and never held by
the touch flag; rule 5 becomes "one memory manager" (ask once at the peak, reservations, tiers); rule 6 is rewritten
for item 9 (f) — the old "one R1 and one R2/R3 at a time" would leave four of the minimum machine's six cores idle;
new rule 10, presentation; §5's build order is replaced by §6's merges (stages 1 and 3 done; stage 3b = S4).

## 9. Measurements that decide, not guesses

| # | Measure | How | Decides |
|---|---|---|---|
| M1 | tap → decode start → swap, per step | `PlaybackTrace` spans on the playcheck, today's code | confirms §0's cause; the before figure for S1 |
| M2 | the ~250 MiB at Undo | playcheck to the Undo phase with `MallocStackLogging=lite`, `leaks --outputGraph` when the sampler passes 1,100 MiB; `vmmap --summary` by region | where S3b's budget entry goes (render copies → in-place repair; IOSurface → presenter; Metal → `gpu` job) |
| M3 | whole vs cut at one window | logic test: same frame drawn both ways at fit and 2× zoom, per-pixel max and count over 2/255 | whether the cut also draws from half levels |
| M4 | what a walk costs at 5000² | device bench (already-unlocked rule): one Test1-like cel, split into dabs / placed-image draws / setup, whole vs 5 bands | band baking (S6) if bands ≤ 1.3× whole, else whole leaves + spill; image-decode cache if images dominate |
| M5 | half-level decode + window draw; quarter-detail walk | device bench, same fixtures as PERFORMANCE §10.2 | the §4 budget lines; Q1's A/B pictures |
| M6 | charged vs resident bytes of a sparse picture | `mincore` over a picture after a render, three Test1-like layers | charge touched pages if the gap ≥ 25% |
| M7 | the stream's cost while drawing | stream on/off pair on the gate (CPU, main spans, memory) | S8's scope |
| M8 | hashing every cel once on open | 300-cel synthetic scene, simulator relative | whether Q2's (a)/(b) costs an acceptable open |
