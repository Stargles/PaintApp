# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — the brush engine, and there is a question waiting for the owner

**[BRUSH.md](BRUSH.md) is the specification. §2 is nineteen owner rulings — read them rather than
re-deriving them**, §12 is the build order and carries a DONE marker per stage, §13 is what is still open.

**Stages 0 through 7 are merged.** TODO (37) describes what that means in one paragraph. **Start at
§12 stage 8** — opacity and flow as separate controls, with the per-stroke buffer §2.11 accepts.

**Two things the owner ruled at the end of the pass and one they are still holding:**

1. **The per-dab regression takes the cheap fix only.** Stage 7 made a dab 35% dearer (MEASURED
   4.018 → 5.437 µs, PERFORMANCE.md §11.2a). Memoise the sensor funnel per dab — worth ~0.3 µs of the
   1.42 — and **stop there**. The larger fix takes the heap array off the hot row and would mean the
   brush editor's curve is no longer the timeline's curve control; the owner chose the reuse. Do not
   reopen that trade.
2. **Stage 9 is driven by contact sheet.** Render candidates through the real stamper, put them in front
   of the owner, build only what they pick. This is the loop that settled §8.4 and it is now the
   instruction for the whole ~24-30 brush set.
3. **The aliased dab edge is with the owner, not filed and not decided.** BUGS.md carries the
   measurement — a hard round dab has only two or three distinct alphas at hardness 0.95, which is
   `hardRound`'s own setting *and* `VectorEraser.supportsCleanCut`'s threshold. **A before/after contact
   sheet was rendered for them at the end of the pass**; if this file is being read before they answered,
   ask again rather than assuming. It matters because the rough ink nib specifies hardness 0.93 purely to
   dodge the jaggies, and stage 9 builds two dozen brushes on top of this dab.

## Ask the owner these

- **The aliased edge, above**, if they have not answered.
- **Drive a real Pencil across the canvas and lean it over.** The simulator cannot synthesise pencil
  input at all, so **non-neutral tilt has only ever been exercised by tests, never by hardware.** Stage 4
  stores altitude and azimuth and stage 7 reads them; nothing has confirmed the hardware end. Ten seconds
  of their time closes a gap no test in this project can.
- **The Import Custom Brush row sits below the fold** in the brush panel and needs a scroll. It works —
  it is just not where they would find it. That is the same shape as the transformation-layer defect
  CLAUDE.md's newest section was written about, so it wants their eye rather than a guess.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**`main` is `b8484fe`. Nothing is in flight; no worktrees, no `tmp/*` branches, nothing uncommitted.**

**Fast tier: 3044 total / 3041 passed / 0 failed / 3 skipped.** It was 2919 at the start of the pass.

**The full suite is green and was run this pass at `77430e1`, after the render path changed: 3159 tests,
3139 passed, 1 failed, 19 skipped, 24:47 on an idle erased machine.** The one failure,
`InterpolationWorkflowUITests`' `testInterpolateModeEndToEndFromGestureToScrub`, **passed clean in
isolation** and is environmental. Its class table is re-taken in CLAUDE.md. **Three stages have merged
since that run** (6, 7 and the docs), so a full run is owed again before the item closes.

**A Release build of `2bef347` is on the owner's iPad and is many merges stale.** Nothing since has
reached the device except the two benchmark runs.

## What the performance question settled, because it is easy to re-open by accident

The owner asked whether reconstructing a thousand brushstrokes would lag or run out of memory.
[PERFORMANCE.md](PERFORMANCE.md) §11 is the answer, MEASURED on their own iPad 9:

- **No memory ceiling.** 48,000 strokes render in 80 MB; geometry is 0.9 MB a thousand strokes. The one
  SIGKILL was the **XCTest runner's cumulative-CPU watchdog, not jetsam**.
- **No main-thread spike.** The re-walk was already off-main — 1.1 ms of main-thread cost at 4,000 strokes.
- **No per-stroke term at all.** 3,200 strokes at 7.67 M dabs cost the same as 32,000 at 7.55 M. **Strokes
  are the owner's unit and dabs are the engine's**, so a brush's spacing moves the ceiling as hard as the
  stroke count does.
- **What was real is latency**, and the **incremental append** made it flat and byte-identical:
  MEASURED on the device, 1,480 → 3.3 ms at 2,000 strokes. **Three quarters of what remains is one 8 MB
  buffer copy, not ink** — so the residue scales with canvas *area*, which is also what keeps the
  vanishing-stroke window open.

**TODO (41) is the rest of it** — every edit that is not an append still costs the whole cel — and
**TODO (42) depends on it**, because live adjustment of a selection is a middle-of-list edit per tick.

## Filed rather than fixed, and each is a decision rather than a backlog entry

- **The vanishing stroke has no small fix.** During a re-walk both of `refreshDisplay`'s relevant arms
  return without touching the image view, and there is one scratch view, so holding the scratch would not
  display the old stroke. The append shrank the window from 1,130 ms to 2.6 ms at 2,000 strokes; it did
  not close it.
- **Undo charges 3-6x what an entry retains**, because copy-on-write shares the sample arrays — 49 steps
  at 4,000 strokes against ~1,032 at the owner's density.
- **Nothing batches per-cel content restores across several cels into one undo step.** `withStructureUndo`
  reaches cel content only through a bespoke keyed field, of which `StructureSnapshot.videoCrops` is the
  working precedent. This is what blocks §2.10's layer and document scopes.
- **`roundness` is declared in §6 and deliberately not built.** It contradicts §3.5's square-mask ruling
  and would mean a second extent through both dab primitives, the pose path and every dirty rect. Nothing
  needs it before stage 9's chisel and flat tips.

## Everything else open, none of it touched this pass

**TODO (39) is the owner's three timeline defects**, all from the device; its freeze lead is the owner's
own observation and worth more than any tracing — **ask them to leave "Record My Actions" running.**
**(40) is onion skin z-order**, where a built fix was dropped unmerged and both sides are on the record.
Three survey defects are in BUGS.md: Flip on a vector layer does nothing and clears the undo stack anyway;
Merge Down on a transformation layer deletes it unprompted; a pose-channel row can raise no box.
**Video's remaining stage is (26) §8 stage 8.** **(21) keyframes**: 5b, 6, 7, 8, 10 and folder-level
transforms. **(29) rendering**: stage 7, the memory audit. (22), (24), (27), (28), (30), (31), (35), (36)
are unstarted and the last group needs a design conversation each.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. **One agent at a time** was the pace for the second
   half of this pass; three is the standing cap.
2. **When something needs the owner's call, ask it through the question prompt** — not as prose at the
   end of a summary.
3. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be".
4. **A replaced path is deleted, not left beside the new one.**
5. **At most one investigation agent at a time.** Building is separate.
6. **Weighty programs may be killed to free the machine.** Standing permission.
7. **Show, do not describe.** The owner ruled on the rough ink nib from contact sheets after prose had
   failed to settle it, and asked for the aliased edge the same way. This is now the default for anything
   whose answer is visual.

## Traps this pass paid for

- **Every brief's prescription is a hypothesis, and five of this orchestrator's were refuted by
  measurement.** Cubic-control-point storage lost to a point-list fit. Rotation buckets in the image cache
  would need 889 of them and lose to a rotated draw anyway. §8.4's eroded tip does not survive the walk's
  union. A positional index into the brush table is exactly what would force the sweep to renumber, so a
  pool handle replaced it. And azimuth was **already** in canvas space — the conversion that was missing
  was the layer transform's.
- **A microbenchmark on the wrong host gives a confidently wrong answer.** Size in the dab cache measured
  worthless on macOS (5.89 vs 5.93 µs) and 5x in the app (76.3 → 14.2). Measure where the code runs.
- **A gate written this pass was itself the banner trap.** `PAINTAPP_BENCH=1` sets the variable for
  `xcodebuild`, not the test runner, so every benchmark skipped under a green banner. It needs
  `TEST_RUNNER_`.
- **A seventh way for a fixture to measure nothing**, and it is aimed at round-trip tests: a `static let`
  holds one value for the life of a process, so encode-then-decode inside that process preserves whatever
  it happened to be. The test was measuring `JSONDecoder`. Say "an earlier launch" by decoding bytes
  written down in the source.
- **A grep for a constructor shape cannot see assignment-shaped sites.** A survey named five places a
  channel would silently vanish; there were ten.
- **`SIMLOCK_SLOTS=1` is a full mutex**, not a light throttle — `seq 1 $SLOTS` is 1-based, so two agents
  both contend for `slot.1`.
