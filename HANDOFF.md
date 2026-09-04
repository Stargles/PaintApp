# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — the session is the brush engine, and §12 stage 4 is where it stands

**[BRUSH.md](BRUSH.md) is the specification. §2 is nineteen owner rulings — read them rather than
re-deriving them**, §11 is what the current engine gives free, §12 is the build order and carries a
DONE marker per stage.

**Stages 0, 1, 2 and 3 are merged.** The path is a refit at a fixed 0.25 pt tolerance and no brush
decides its density; per-dab randomness is `hash(seed, arcLength)` measured in **brush widths**; grain
does not exist; and `DabTarget` has an image primitive with a tinted size-keyed cache. **Stage 4 — the
sample record — was in flight when this was written**: `git worktree list` and `git branch -a` before
trusting that, and `git fetch` first, because `origin/main` is a shared ref.

**The owner ruled the build order stands** and will not have the rough ink brush pulled forward:
*"The brush will get done once the brush engine which allows it to exist is done, along with the other
brushes. Focus on the engine for now. I want a clean and well designed architecture first, which cleanly
replaces the old one."*

**Four rulings shape everything and are the ones a session will otherwise re-derive.** Randomness is a
hash of arc length **in brush widths** and never a stream — §4, and the unit is what survives a lasso
resize, a canvas resize and a layer transform. **Tilt ships** (§2.7, reversed on the memory measurement)
and lands in stage 4 as two more channels. Brushes deduplicate into a document-level table, frozen per
stroke, with an explicit apply-to-existing verb. And the **rough ink nib is a dynamics effect, not a tip
effect** — §8.4, refuted by measurement, which is what §2.17's wavelength and §2.18's `density` exist for.

## State

**`main` is `eeefdee`. Fast tier: 2968 total / 2965 passed / 0 failed / 3 skipped.** It was 2919 at the
start of the pass.

**No full suite was run this pass, and the render path changed — the next session owes one.** The
incremental append rewrote how a vector cel reaches its pixels; that is exactly the kind of change
CLAUDE.md says to run the full suite behind. Erase the simulator immediately before it.

**A Release build of `2bef347` is on the owner's iPad and is now many merges stale.**

**One measurement is missing because the device was locked**: the incremental append's device row.
§11.8 of [PERFORMANCE.md](PERFORMANCE.md) carries the exact command and the hardware-independent part.

## What the performance question settled, because it is easy to re-open by accident

The owner asked whether reconstructing a thousand brushstrokes would cause lag spikes or memory
crashes. [PERFORMANCE.md](PERFORMANCE.md) §11 is the answer, MEASURED on their own iPad 9:

- **No memory ceiling.** 48,000 strokes render in 80 MB; geometry is 0.9 MB a thousand strokes. The one
  SIGKILL was the **XCTest runner's cumulative-CPU watchdog, not jetsam**.
- **No main-thread spike.** The re-walk was already off-main: 1.1 ms of main-thread cost at 4,000 strokes.
- **No per-stroke term at all.** 3.16 µs a dab and nothing else — 3,200 strokes at 7.67 M dabs cost the
  same as 32,000 strokes at 7.55 M. **Strokes are the owner's unit and dabs are the engine's**, so a
  brush's spacing moves the ceiling as hard as the stroke count does.
- **What was real is latency**, and it starts below the owner's estimate: pen-up-to-pixels was ~142 ms at
  their own measured 190-stroke density. The **incremental append** makes it flat and byte-identical —
  1,129.6 → 2.57 ms at 2,000 strokes — on a `Damage` seam where all 16 mutation sites declare what they
  changed. An appended eraser, fill, image, video or text **is** associative with the flattened base;
  only a paint stroke inside a blend-mode run is not.

**TODO (41) is the rest of it** — every edit that is not an append still costs the whole cel — and
**TODO (42) depends on it**, because live adjustment of a selection is a middle-of-list edit per tick.

## Filed rather than fixed, and each is a decision rather than a backlog entry

- **A hard round dab is fully aliased, and it starts at 0.95** — `hardRound`'s own hardness, not a
  degenerate endpoint. Hidden by ~10:1 dab overlap; it stops hiding when a brush edge is meant to be
  seen, which is what the rough ink nib is. Fixing it moves pixels under a dozen parity tests.
- **The vanishing stroke is real and has no small fix.** During a re-walk both of `refreshDisplay`'s
  relevant arms return without touching the image view, and there is one scratch view, so holding the
  scratch would not display the old stroke. The append shrank the window from 1,130 ms to 2.6 ms at
  2,000 strokes; it did not close it, and what remains scales with canvas area.
- **Undo charges 3-6x what an entry retains**, because copy-on-write shares the sample arrays — 49 steps
  at 4,000 strokes against ~1,032 at the owner's density.
- **`ProjectStore`'s texture copy walks the palette, not the drawing.** Correct today only because a
  custom brush can never leave the palette, which §2.10's minting ends. Belongs to stage 6.

## Everything else open, none of it touched this pass

**TODO (39) is the owner's three timeline defects**, all from the device; its freeze lead is the owner's
own observation and worth more than any tracing. **Ask them to leave "Record My Actions" running.**
**(40) is onion skin z-order**, where a built fix was dropped unmerged and both sides are on the record.
Three survey defects are in BUGS.md: Flip on a vector layer does nothing and clears the undo stack
anyway; Merge Down on a transformation layer deletes it unprompted; a pose-channel row can raise no box.
**Video's remaining stage is (26) §8 stage 8.** **(21) keyframes**: 5b, 6, 7, 8, 10 and folder-level
transforms. **(29) rendering**: stage 7, the memory audit. (22), (24), (27), (28), (30), (31), (35),
(36) are unstarted and the last group needs a design conversation each.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. **Three tasks at once.**
2. **When something needs the owner's call, ask it through the question prompt** — not as prose at the
   end of a summary.
3. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be".
4. **A replaced path is deleted, not left beside the new one.**
5. **At most one investigation agent at a time.** Building is separate.
6. **Weighty programs may be killed to free the machine.** Standing permission.
7. **Show, do not describe.** The owner ruled on the rough ink nib from contact sheets after prose had
   failed to settle it, and reversed a ruling on seeing an A/B image.

## Traps this pass paid for

- **Every brief's prescription is a hypothesis.** Three of this orchestrator's were refuted by
  measurement and one spec section with them: cubic-control-point storage, rotation buckets in the image
  cache, and §8.4's eroded tip. A fourth was refuted the other way — size *does* belong in the cache key,
  which a macOS microbenchmark said was worthless and the app measured at 76.3 → 14.2 µs a dab. **Measure
  in the place the code runs.**
- **A gate written this pass was itself the banner trap.** `PAINTAPP_BENCH=1` on the command line sets
  the variable for `xcodebuild`, not for the test runner, so every benchmark skipped under a green
  banner. It needs `TEST_RUNNER_`.
- **`SIMLOCK_SLOTS=1` is a full mutex**, not a light throttle — `seq 1 $SLOTS` is 1-based, so two agents
  both contend for `slot.1`. Correct for a shared device and expensive when the machine is idle.
- **Diffing a branch against a moved `origin/main` measures evolution, not unmerged work.** A benchmark
  branch read as deleting the previous stage's files; it was simply older.
- **A benchmark class must be opt-in.** `xcodebuild` distributes per test *class*, so tests measuring
  23.5 s and 35.8 s apiece would set the full suite's critical path alone — and the runner's watchdog
  kills a process that runs two in a row, which reads as environmental.
