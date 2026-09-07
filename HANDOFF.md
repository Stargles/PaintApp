# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks **in queue order — the top of the list is what to do next**;
[BUGS.md](BUGS.md) is what we find.

## Start here: three branches are quarantined and NONE of them may merge unverified

**This is the whole job of the next session, before any new work.** Three branches hold finished-looking
work whose authors were **killed mid-task by a usage limit**. Their reasoning is unrecoverable. The owner's
standing requirement, stated 2026-09-06:

> *"I need your complete and absolute confidence that all of their work is thoroughly examined down to
> each line before we allow it to merge with main. Remember: the single most important design
> consideration of this entire project is that the architecture and repository are clean, organized, and
> up to date, with absolutely zero tolerance for defects."*

| branch | commits | rebased on `1277909`? | verified? |
|---|---|---|---|
| `tmp/playback` | 8 | **yes** | **no — its fast tier was killed before it finished** |
| `tmp/fps` | 5 (incl. 1 WIP) | no | no |
| `tmp/prune` | 5 (incl. 1 WIP) | no | no |

All three working trees are **clean**, no simulator clones exist, and the stash is empty. Nothing was lost.

**Audit each one adversarially before merging, with an agent that did not write it.** Aim the audit at
*tests*, because **every serious defect this session was in a test, not in app code**:

- two load-bearing assertions **commented out** with `// DIAG: temporarily disabled` — the test ran green
  against a dead feature; a mutation makes a test go red, this made a test stop being a test;
- a ruler that took the centroid of dark pixels on a row **dominated by the black tool rail and the grey
  layers rail**, so it measured chrome: the ink travelled 260 px right and the number went *down*;
- a "regression test" that was a **characterization of the defect** — it asserted the drag moved the block
  0 pt, so it was green against the broken app, and TODO called it the regression test;
- an assertion **true of mathematics rather than of the code**, and another **true at the wrong level**.

For every assertion on these branches ask *"if this went red, would the code be wrong?"* and then **prove
it by mutation** — the killed sessions' own sweeps may never have run. **Commit before mutating.**

### `tmp/playback` — TODO (53), the owner's own bug, and the most valuable of the three
The orchestrator read the app-code diff and believed it sound; **that is not evidence and must be
re-derived.** What it does: `sandwichEngagesOnCanvas` now also engages on a new `hasContainerPoseInForce`,
because Core Animation draws a flat row of layer hosts and cannot move one sibling by a transformation
layer above it — so the only thing showing the pose was `updateInterpolationPreviews` rasterizing posed ink
into the host's slot, **a canvas-sized main-thread render per distinct pose, and a keyframed move mints a
distinct pose every frame.** Claimed **71.9 ms a frame against 3.7 ms to read the bake** (PERFORMANCE.md
§14). It also fixes a second bug found on the way: a raster layer under a transformation layer **moved only
in the bake and never on the canvas**.

**Audit these four points specifically.** (1) Is `LayerPose.movesItsContents` genuinely frame-invariant —
can it disagree with what renders at some frame? It assumes two resting keys cannot interpolate to anything
but rest; CLAUDE.md records an overshooting bezier handle inside a segment being silently flattened, so do
not take that on faith. (2) The `guard !host.isBlanked else { continue }` is placed **before** the key check
deliberately; verify that argument against `updateSandwich`'s blanking path and its "trap 1". (3) Engaging
the compositor changes the rendering path for *any* document with a container pose — what regresses?
(4) Verify the numbers: `autoreleasepool`, Debug-vs-Release, idle machine, MEASURED/INFERRED labels.

`PlaybackTickBench.swift` holds eleven `print("PLAYBACK | …")` lines — confirm the file is excluded from
the fast tier **by filename** and gated behind `XCTSkipUnless`, which is the convention, not scaffolding.

**A cel's own pose channel is deliberately NOT fixed** and has the identical defect at 73.6 ms a frame. It
is filed in BUGS.md with what must be measured first (a drag showing a stale composite). That is honest, not
an oversight.

### `tmp/fps` — KEYFRAMES §8 stage 7, part-built
An editable fps and a live take recorder. **It edited `TODO.md`, which its brief forbade — revert that.**
Its last commit is WIP: `ValueRecordingLogicTests.swift` may not be wired into `project.pbxproj`, and a test
file that is not listed there is **silently never compiled and never run** while the suite still prints
`** TEST SUCCEEDED **`. Reconcile by count before believing anything. Stage 10 (§7, the timing recorder)
sits directly on this stage and is described as small.

### `tmp/prune` — TODO (45), documentation only
Spec corrections plus the removal of four leftover `FREEZEDIAG`/`MENUDIAG` `NSLog` scaffolds. Touching
`TODO.md` was permitted for this one. Lower risk than the other two, but the same rule applies: a spec sweep
of this file's own kind once produced **130 false positives**, because the specs cite sources by a
`PaintSoftware/`-relative shorthand as a deliberate convention rather than as rot.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

`main` is at **`1277909`**. Fast tier there: **3435 total / 3432 passed / 0 failed / 3 skipped**, reconciled
exactly against 3435 static `func test` **declarations** across 146 files. A plain `grep -c "func test"`
over-counts by 3 — three files say the phrase in prose. **The full suite has not been run this pass.**

A Release build of `7ad5a9f` is on the owner's iPad from 2026-09-06, provisioning valid until 2026-09-12.
**Everything below is newer than that build and the owner has seen none of it.**

## What shipped this pass

Six items closed and left [TODO.md](TODO.md) whole: **(39)** the timeline freeze, **(51)** onion-skin
opacity, **(52)** the hidden-layer merge, **(47)** the pen-only finger tap, **(12)** animated Distort, and
**(26)** import videos. Twelve items became nine.

- **(39) The timeline freeze.** Four `.popover` menus became `AnchoredMenu`, drawn inside the timeline's own
  hierarchy. Dismissal is a window recogniser that reports the touch-down point and **immediately fails**
  with `cancelsTouchesInView = false`, so the touch that dismisses still reaches the track: one drag, not
  two. MEASURED — menu up, one 250 pt drag closed it *and* scrolled the ruler from frames 1–28 to 18–45.
  **Five more `.popover`s have the same gate and are filed in BUGS.md**, unfixed because three are colour
  pickers whose chrome would visibly change — the owner's own call for the timeline's four.
- **(12) Animated Distort.** `PoseQuad.affineOrLinearised` is deleted; a pose answers a `PoseMap` that is
  affine **or genuinely projective**, demoted at every constructor. MEASURED: the old linearisation
  displaced both bottom corners of a keystone by **164 px**, and local scale spans 6.09x across the quad
  against one centre scalar — **218% wrong** at the far end. Thirteen mutations, thirteen red.
- **(26) Import videos** closed with the bake verb; **(21)** gained the folder transform entry and the graph
  editor's node delete and tap-to-add.
- **(52) was refuted, not built** — the guard it asked for was already on `main`, landed nine hours before
  the item was filed.

## The trap this pass paid for, and it cost the owner real money

**Subagents spawned subagents.** Three briefed agents became **seven running agents**, because
`general-purpose` carries the Agent tool and no brief forbade delegating. Combined with an orchestrator that
had misread the budget as "1 Opus **plus** 2 Sonnet" when it is **1 Opus *or* 2 Sonnet**, this burned
millions of tokens and hit the usage limit, killing five agents mid-task and creating the quarantine above.

**Every brief must say: do not spawn subagents.** And the cap is **one Opus, or two Sonnet, total.**

Two smaller ones worth keeping: a worker's **completion notification fires while it is still waiting on its
own background run**, so harvesting then makes its worktree vanish under it — one worker concluded a rival
session had raced it. And **an agent's own triage runs evict the full run's `.xcresult`**, so pull a count
immediately after the run that produced it or it is gone.

## Waiting on the owner — the next session's agenda after the audits

- **(31) The 16383² canvas.** Build a downscaled display proxy, or lower `maxCanvasExtent` — TODO calls the
  latter the cheaper answer if the owner does not need 16k. A deferred A/B is owed before the lag ruling.
- **(22) Select multiple cels.** No design at all; the menu row is `.disabled(true)` with an empty action.
- **(21) Animation-group membership editing.** §2.29 rules that splitting one animated group into two is *"a
  different feature"*; retagging is that question from the other side.
- **(41) / (42).** The owner has accepted (41) where it stands, but **(42) is blocked on it** — a live
  preview over a selection is a rewrite in place, which no caller's rectangle can bound. Worth asking
  whether (42) matters enough to reopen (41).
- **The pencil half of (47)** cannot be driven by any test here — XCUITest cannot synthesise a pencil touch.
  Ten seconds on the owner's iPad settles it.
