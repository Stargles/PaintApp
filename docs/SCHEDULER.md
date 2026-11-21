# SCHEDULER — real-time rules for every piece of work in PaintApp

Status: **rules ruled; stage 3 (one budget) built on `tmp/nov21-budget`, 2026-11-21** (`Engine/MemoryBudget.swift`). The owner delegated the rules: *"I'll let you pick
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
| **R1 answer** | the result of an action the artist just finished: a stroke landing, an Undo/Redo picture, a fill, a Move lift and set-down, a Liquify step, a tool switch | background, highest QoS | **firm**: ≤ 100 ms on the iPad 9 at the owner's 5000² scene; late is a bug, never a freeze |
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
   composite (RENDER.md §3.8) is the existing shape for that.
4. **Latest wins.** Work made stale by a newer edit is cancelled, not finished: a second stroke cancels the
   first stroke's pending re-render of the same cel, a scrub cancels the bake of the frame it left.
   Cancelling stale work is also the main way this design saves memory.
5. **One budget.** Every job asks one admission point for its memory (the 192 MiB iPad 9 budget,
   physical/16, and backboardd's 1,850 MiB) before it allocates. R1 that cannot be admitted says so (the
   notices that exist), R2/R3 wait. This replaces the scattered `hasHeadroom` checks.
6. **Bounded parallelism.** The iPad 9 has two performance cores. At most one R1 job and one R2/R3 job run
   at a time; the stream counts as one R2 job. More threads than cores only adds switching and memory.
7. **The stream is a guest.** Fixed budget per frame, decode off main, a late frame is dropped and never
   queued, and it never runs above R1. With a stream on, drawing must feel exactly as it does with it off.
8. **Every job is named and measured.** The recorder logs each job's class, time waiting and time running,
   and every main-thread span by name. "Unattributed main time" is itself a failure the recorder reports.
9. **A gate proves it.** A scripted device burst (strokes, pans, Undos, fills at 5000² × 5 layers, stream
   on) asserts the max main-thread pass and R1 latency; it runs before every install, next to
   `DeviceStressUITests`.

## 4. Cost

The scheduler itself is small: four priority lanes, an "is a touch down" flag, and a cancel token per job —
microseconds a job and a few KB. It should **lower** memory: rule 4 drops stale work before it allocates,
rule 6 stops three canvas-sized jobs coexisting, and rule 5 makes the budget one number instead of twelve
guesses. The real cost is migration: each heavy job has to be made cancellable and cut into checkpoints.

## 5. Build order — each stage ships on its own and is checked on the iPad

1. **Stop the bleeding** — rules 1, 2 and 3 for the bake and thumbnails (the cause of the Nov 17 hitches,
   if the current investigation confirms it), plus rule 8's main-thread attribution.
2. **Scheduler core** — the four lanes, the touch flag and cancel tokens; move R1 work (stroke landing,
   Undo, fill, Move, Liquify) onto it with latest-wins.
3. **One budget** — rule 5; retire the per-feature `hasHeadroom` checks.
4. **Guests and the rest** — stream (rule 7), save, export, onion, sandwich, project load; delete the
   per-subsystem queues.
5. **The gate** — rule 9 on the device.

## 6. What this does not cover

The recurring canvas freeze is a gesture-recognizer state bug (a pan left `.ended` after a touch was
cancelled and began again mid-gesture, flight 2026-11-17 19:11), not a scheduling one, though long main
stalls make that kind of touch sequence likelier. It is fixed on its own (TODO.md).
