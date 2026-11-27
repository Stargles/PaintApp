# SCHEDULER — real-time rules for every piece of work in PaintApp

Status: **rules ruled; stage 3 (one budget) merged 2026-11-21** (`Engine/MemoryBudget.swift`); **the build is
designed in [SCHEDULER_DESIGN.md](SCHEDULER_DESIGN.md) (2026-11-25)**; **S1 and S3a built 2026-11-25, S2 2026-11-26, S3b 2026-11-27** — the core in
`Engine/Scheduling/`, frame reads as R1, rule 10's presenter (`CanvasPresenter`); layer pictures repaired in place, Undo
from kept pixels, cancellable walks with no lock across them, and no wait left on the main thread (a fill tap behind a
fill still drawing is queued) — scheduler and memory manager as one page, its §6 is the build order. The owner delegated the rules: *"I'll let you pick
out the rules for this because if I explicitly define it I might miss something critical. Basically, all
the UX stuff the user interacts with should be hard or firm real time like moving the canvas, canvas
updating, drawing strokes, erasing, etc. To make this so, everything that can run on a background thread
should run on the background thread."* The owner's first prompt for this project asked for "real time";
this document is what that word means here, and it binds every feature from now on, built or not.

## 1. Why this exists

There is no scheduler today. About 17 subsystems each own a serial `DispatchQueue` with a QoS picked when
it was written (stroke render, Liquify, canvas pixels, save, export, stream decode and client at
`.userInitiated`; frame bake and the recorder at `.utility`; interactive fill at `.userInteractive`; five
with no QoS at all: sandwich, onion, on-top stream surface, layer fill, project load). None knows about the
others, nothing yields while a finger or pencil is down, and about 12 sites can block a thread on another
(`.sync`, `wait`, `waitUntilCompleted`). MEASURED on the owner's iPad 9, 2026-11-17 (Test1, 5000², five
vector layers, stream on): main-thread run-loop passes of 113–796 ms every few seconds while drawing, with
a 5.3–8.8 s frame bake running at the same time. Every lag, hitch and black-out report this month is one
of these rules being broken somewhere.

## 2. The four classes

| Class | What | Where it runs | Deadline |
|---|---|---|---|
| **R0 frame** | touch and gesture handling, canvas pan/zoom/rotate, the live stroke and eraser under the pencil, putting an already-made picture on screen | main thread + the display | **hard**: inside one 60 Hz frame (16.7 ms), of which main may use ≤ 4 ms |
| **R1 answer** | the result of an action the artist just finished: a stroke landing, an Undo/Redo picture, a fill, a Move lift and set-down, a Liquify step, a tool switch, **the frame a step or play asks for** | background, highest QoS | **firm**: ≤ 100 ms on the iPad 9 at the owner's 5000² scene; late is a bug, never a freeze |
| **R2 soon** | things on screen that may lag a moment: layer and cel thumbnails, onion skin, the current frame's cache, stream frames | background, middle QoS | soft: ≤ 500 ms, drop or skip when late |
| **R3 later** | work nobody is looking at yet: other frames' bakes, prefetch, autosave writing, version thinning, export, recorder writes | background, lowest QoS | best effort |

## 3. The rules

1. **Main never waits.** No `.sync` onto any queue, no semaphore, no `waitUntilCompleted`, no lock that
   background work holds for longer than a pointer swap, no IOSurface `isInUse` spin. If main needs a
   result that is not ready, it shows the last good picture and is told when the new one lands.
2. **Main never does canvas-sized work.** No allocation, decode, composite, rasterize, copy or flatten whose
   size grows with the canvas. Main swaps pointers to pictures made elsewhere.
3. **A touch outranks everything.** While a finger or pencil is down, and for 250 ms after the last one
   lifts, R3 pauses at its next checkpoint and R2 runs only on what is visible. Long work (a bake, an
   export, a flatten) is cut into checkpoints of ≤ 50 ms on the iPad 9 so it can stop; the striped
   composite (RENDER.md §3.8) is the existing shape for that. **R1 is never held by the touch flag** —
   the touch is usually what asked for it (a frame step's read waited 250–500 ms for its own tap).
4. **Latest wins.** Work made stale by a newer edit is cancelled, not finished: a second stroke cancels the
   first stroke's pending re-render of the same cel, a scrub cancels the bake of the frame it left.
   Cancelling stale work is also the main way this design saves memory.
5. **One memory manager.** Every job asks one admission point for its **peak** before it starts and is
   granted it whole or not at all; nothing is refused part-way and no job holding memory waits for more.
   R0 and R1 run on reserved memory and never wait on disk; R1 that cannot be admitted says so (the
   notices that exist); R2/R3 stay queued holding nothing. Features state facts (how a thing comes back,
   what it costs, when it is next used, which stand-ins it accepts); only the manager evicts, spills and
   loads (SCHEDULER_DESIGN.md §3).
6. **Every core, bounded by cores and memory.** Core counts are read from the machine. One fast core is
   always left for the pencil, the main thread and the window server while a touch is down; one R1 job runs
   at a time and fans out in tiles across the rest; R2/R3 take efficient cores, and all but one core when
   idle. How many tiles run is the smaller of free cores and the memory each tile needs. (The minimum
   machine, the iPad 9's A13, is 2 fast + 4 efficient cores; "one job at a time" left four of them idle.)
7. **The stream is a guest.** Fixed budget per frame, decode off main, a late frame is dropped and never
   queued, and it never runs above R1. With a stream on, drawing must feel exactly as it does with it off.
8. **Every job is named and measured.** The recorder logs each job's class, time waiting and time running,
   and every main-thread span by name. "Unattributed main time" is itself a failure the recorder reports.
9. **A gate proves it.** A scripted device burst (strokes, pans, Undos, fills at 5000² × 5 layers, stream
   on) asserts the max main-thread pass and R1 latency; it runs before every install, next to
   `DeviceStressUITests`.
10. **The screen never mixes pictures.** One presenter owns what the canvas shows and replaces it whole:
   a new set goes up in one transaction once every part of it is ready, or not at all; the last complete
   picture stays meanwhile.

## 4. Cost

The scheduler itself is small: three job lanes beside the main thread, an "is a touch down" flag, and a
cancel token per job — microseconds a job and a few KB. It should **lower** memory: rule 4 drops stale work
before it allocates, rule 5 admits each job's peak once so canvas-sized jobs cannot pile up half-admitted,
and the manager keeps three layer pictures where there were one per layer (SCHEDULER_DESIGN.md §3.1). The real cost is migration: each heavy job has to be made cancellable and cut into checkpoints.

## 5. Build order

Stage 1 (stop the bleeding: the bake paused under a touch, thumbnails off main, main-thread attribution) and
stage 3 (one budget) are merged. The rest — stage 2 (the core), stage 3b (the memory manager, TODO item 9),
stage 4 (guests) and stage 5 (the gate) — is SCHEDULER_DESIGN.md §6's merges S1–S9, in that order: S1 frame
steps (core, R1 frame reads, presenter), S2 bake file with levels, S3a/S3b R1 work and Undo, S4 memory
manager, S5 two merged pictures, S6 bake throughput, S7 guests, S8 stream, S9 device gate.

## 6. What this does not cover

The recurring canvas freeze was a gesture-recognizer state bug, not a scheduling one, and was fixed on its
own (BUGS.md, "The canvas stops answering two fingers").
