# SCHEDULER_DESIGN — the scheduler and the memory manager, one page

Status: **design, not built (2026-11-25, `tmp/nov25-sched`).** [SCHEDULER.md](SCHEDULER.md) is the rules;
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
| Sandwich halves, eyedropper | `CanvasView.sandwichQueue` | serial, no/userInit. | 2–3 pictures | R2 | W | O(layers) mint |
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
