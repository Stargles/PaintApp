# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## State

`main` is clean at `0b90718`, no worktrees, no branches, no stray simulators.

**Fast tier: 2316 declared, 2316 executed, 2313 passed, 0 failed, 3 skipped.** Count it statically at
your own base before trusting any number in a brief, including this one.

**The full suite was run this pass, at `41eafa9`: 2414 total, 2403 passed, 5 failed, 6 skipped.** Four
failures re-ran clean in isolation and are environmental. The fifth,
`PerfBaselineTests.testWhatOneFrameOfTheBoxKnobCosts`, **failed again in isolation and is still
unresolved** — but its isolated re-run was itself contended, the measured value walks toward the budget
as load drops (1.111 ms → 0.913 ms against 0.833 ms), nothing in `MoveBoxInk.bounds`' path has changed
since the last clean run, and it passes on the device. **It needs one isolated run on a genuinely idle
machine.** That is thirty seconds and nobody has had an idle machine to spend.

**Six commits landed after that run**, including all of stage 2, so the suite has not been run on the
tree as it stands.

**The iPad carries a Release build of this pass.** It is the first build the owner has had since
`7c38ba2`, so it is also their first with the 16k crash fix and the playback-clock hoist.

## What is being built: TODO (29), the background renderer

[RENDER.md](RENDER.md) is the specification. **§1 is the ask in the owner's own words, §2 is sixteen
rulings, §3 is the design, §5 is the build order.** Read §2 rather than re-deriving it.

**Stages 0, 1 and 2 are merged. Stage 3 — chunked compositing (§3.4) — is next.** It needs
`renderSources(subset:)`, which is now a parameter on the recipe's resolve rather than on a main-actor
function. §5 stage 3 names the fixture it has to pass and, more importantly, the fixture that must
**fail** if any of the four chunking rules is deleted.

Stage 2 shipped `Engine/FrameRecipe.swift`: the snapshot is minted on the main actor in O(layers) with
no pixel work and resolved off it. MEASURED, simulator/Debug: **174-313 ms of main-thread work at
pen-up down to 0.2 ms**. Sized on the owner's iPad in Release: a 36.3 ms snapshot and a 70.3 ms
committed re-render both left the main thread.

## What this pass established, and would otherwise be re-derived

- **The 16k canvas is a display bug, not an allocation one.** A 16383² `VectorCanvas.render()` is
  MEASURED at 143.5 ms on the device *with the ink present* — a `CGBitmapContext` is lazily committed,
  so the 1 GiB buffer is cheap to hold and expensive to walk. Anything that starts "the allocation
  fails" is starting from a refuted premise.
- **Nothing set `minificationFilter`, and that was silently destroying ink at 4096² and above** — a
  5-point brush point-sampled to `fitScale` left zero ink at 4096², 8192² and 12288². Fixed at nine
  sites; `PaintSoftwareUITests/CanvasLayerFilterLogicTests.swift` pins it by scanning source, because
  the views are not compiled into the test target.
- **16383² still cannot be composited at all**, and no fix above touches that. It needs a downscaled
  display proxy. Until then the 16k canvas is unusable while every size below it works.
- **The fast-tier selector is filename-derived and loses tests in two directions** — a hand-rebuilt
  filter drops `PerfBaselineTests`, and a class in a file of another name is never selected. Both print
  green. CLAUDE.md now carries it; the cure is reconciling executed against a static count.
- **`PixelOps.parallelMap`'s fan-out is 1.41x on the device, not the ~3.5x the simulator implied** —
  the A13 is 2 performance cores plus 4 efficiency ones. PERFORMANCE item 9(b) carries the correction.
  It makes moving work off the main thread worth more, not less.
- **The compositor budget on the owner's iPad is 183.7 MB**, where the docs assumed 192.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do.
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned.
3. **A replaced path is deleted, not left beside the new one.** RENDER §2.15 in the owner's words:
   *"very clean and non-redundant, with no peculiarities, and no legacy code left by the previous
   functionality."*
4. **At most one investigation agent at a time.** Building is separate; this is about investigations.

## Traps this pass paid for

- **Three simulator-bound runs at once took the machine to 0.5% idle, and that voided every timing
  number taken during them** — including the per-class table CLAUDE.md keeps asking to have re-taken,
  which came out 5-6x inflated and had to be discarded. Pass/fail survives contention; nothing else
  does. The cap of three in flight is about this machine, not about the plan.
- **A full run's xcresult is evicted by the triage runs that follow it**, so pull the per-class table
  immediately or lose it.
- **`origin/main` is a shared ref**: any session's fetch repoints it, so `git reset --mixed
  origin/main` staged a revert of another session's nine merged files. Reset to a sha you recorded.
- **Two orchestrator prescriptions in briefs were wrong, and both were caught by the worker measuring
  rather than reasoning.** The recipe was told to capture `VectorCanvas.cachedImage` at mint and fall
  back to frozen values — which loses the memo in exactly the pen-up case the stage exists for, because
  the commit has just nilled it. And the scratch-window snippet padded the *unexceeded* axis by half
  its own extent, which keeps the window square from a smaller seed; skipping that axis is what makes
  the band. **A brief's prescription is a hypothesis in the same way its numbers are.**
- **A pin that draws through the code it is checking proves nothing.** Stage 2's parity oracle called
  `PixelOps.rasterize`, so it passed with the defect injected. Both fixes this pass were mutation-tested
  against a deliberately broken implementation, committed before mutating.

## Everything else open

**The owner's asks** are in TODO. **(12) was missing entirely and is restored** — LASSO_MOVE §3 stage 4
still lists placed-image stretch (3c), Distort (stage 5) and the `FloatingPieceOverlayView` port.
**(21) pointed at stage 4 and now points at stage 5**, which is what the owner ruled; the width rule
`sqrt(|det|)` has to be settled before that stage starts. **Distort is one feature reachable from two
items** — LASSO_MOVE stage 5 and KEYFRAMES 5b. (31) holds the three large-canvas symptoms, now in three
different states. (32)-(34) are small. (22), (24), (35)-(37) and (26)-(30) are unstarted, and the last
group needs a design conversation each.

**Deferred by the owner, not refused:** scaling the stroke sample gate by zoom, which would fix the 8x
dab explosion when zoomed out (352 dabs per screen inch at 2048², 2815 at 16383²). It is a permanent
quality trade — coarser stored geometry feeds interpolation and the vector eraser — so it wants an A/B
the owner can look at, not a number.

**BUGS.md's memory audit** is twelve ranked sites, all still open, plus PERFORMANCE §9's eight new ones
from this pass's audit. The cheapest unclaimed one is two lines: a dab straddling a clamped canvas edge
rebuilds the scratch window every time, because `windowRect.contains` can never be true there.
