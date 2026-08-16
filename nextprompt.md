# Handoff — UX pass round 2 (2026-08-16)

You are picking up an owner-feedback pass. Read this whole file, then `git fetch` and check the
branch tips below against reality — **assume this file is stale until you have verified it**, per
CLAUDE.md's own warning about handoff notes.

## Read these first

1. [CLAUDE.md](CLAUDE.md) — operating manual. The simulator, test-count and `simlock.sh` sections
   are load-bearing and were all learned the hard way.
2. [BUGS.md](BUGS.md) — open issues, including several this pass added or amended.
3. This file.

## State of the work

`tmp/uxpass2` is the integration branch, **7 commits ahead of `main`, fast-tier green at 947 tests /
0 failures** (verified twice, second time covering the block-drag + timeline-menu combination since
both touched `TimelineTrackView.swift`).

Landed on `tmp/uxpass2`:

| Owner item | What shipped |
|---|---|
| 2 — value layer Mode → Blend Mode | One merged row; `setLayerBlendMode` clears the grade, mirroring `setMixBlendMode`/`setNodeEffect` |
| 5 — remove Adjust icon | Icon, enum case and `StubToolPanel.swift` deleted; the panel was a placeholder with no feature |
| 6 — timeline frame cap | `goToFrame` raises `sceneFrameCount` instead of clamping; playback bounds use `contentEndFrame` and are unaffected |
| 3a/3b — add-drawing menu | Gap tap now needs the same two-stage gate the cel tap had; three popovers collapsed into one |
| 7 — block resize + shuffle | Push-not-shrink on both edges, cascade stops at first non-collision, length preserved; shuffle UI |
| — | Stale `EffectLayerLogicTests` repair + new test for the clearing behaviour |
| — | `tools/simlock.sh` test mutex |

**Branches not yet merged.** All were cut from `ea31aa2`, so **rebase each onto `tmp/uxpass2` before
`--ff-only` merging**, in this order (later ones touch files earlier ones changed):

- `tmp/compperf` @ `2797363` — 7 commits. **Blocked on two gates, see below.**
- `tmp/shapefix` @ `9537209` — 4 commits. **Blocked on an owner recording, see below.**
- `tmp/layergest` @ `0ae718b` — 2 commits. Was triaging one UI failure
  (`testOpeningALayerMenuPutsMaskAndFillControlsOnTheRows`) in isolation; get that verdict first.
- `tmp/stamping` — was at base when this was written; the agent may not have committed. Check.

Worktrees exist for all of the above plus `tmp/blockdrag`, `tmp/efftest`, `tmp/tlmenus` (all three
already merged — **remove those three worktrees and delete their branches**).

## The two big findings, so you do not re-derive them

**1. The compositor was never on the GPU.** `Compositor.backend` defaulted to `.coreGraphics` and
nothing in the app ever set `.metal` — only test files did. The Metal compositor was complete,
parity-tested, and dead in the shipped binary. `tmp/compperf` fixes the upload cost first (it had no
cache and rebuilt every layer's bytes per composite, ~100 MB/frame), then flips the default.
Measured, Debug/simulator, 6 layers at 2048²: one repaint 491.8 ms → **31.3 ms**; the same plus one
adjustment layer **7047 ms → 18.8 ms**.

Dirty-rect scissoring was **deliberately not built**, and the reasoning should survive: per-layer GPU
cost is now 0.3–0.8 ms while the *fixed* per-frame cost is ~11.4 ms (69–86% of a frame), and that
fixed part is the readback that copies the finished image off the GPU. Scissoring cannot touch it.
**The next real win is eliminating the readback** — render into a `CAMetalLayer` — and dirty rects
become worthwhile only after that.

**2. The "stroke turns into a line" bug is a stub, not a lag spike.** The owner worked this out and
they were right. There is no stall: the popover teardown was **measured at 0.43 ms** against a
hypothesis of ~800 ms. What happens is that touch delivery to the stroke *stops* a few samples in
with **no terminal callback at all — not even cancel** (which is why the stub survives the pen lift
and dies only when the next stroke rebuilds the scratch). The 0.8 s "freeze" the owner perceived is
exactly the shape-hold constant elapsing with nothing left to reset it. The eraser shows the same
stub without a line, because the shape detector is gated to pen/pencil.

**The stub is traced but NOT fixed.** That is the most valuable piece of open work. Two candidates
reading could not separate: a mid-sequence `isUserInteractionEnabled`/removal flip (`reconcileLayers`
writes both), or UIKit dropping the sequence via the popover's presentation overlay. `BUGS.md` has
the write-up. Note `StrokeGestureRecognizer.failTrackedStroke` is an existing BUGS.md entry — a path
that fails an already-begun stroke which *nothing in the suite reaches* — and it is the right shape
for this.

## Blocked on the owner — ask for these

1. **An ActionRecorder capture of a pencil held still for two seconds.** `tmp/shapefix` replaces the
   wall-clock shape-hold timer with one measured in `UITouch.timestamp`, which is correct under both
   the old and new diagnosis. Its one assumption is that a parked pencil keeps sending samples.
   XCUITest's synthetic touch reports intermittently under load, so the simulator cannot settle it.
   `BUGS.md` says exactly what to count in the JSONL. **Do not merge `tmp/shapefix` without this.**
2. **A big-canvas, many-layer test on the actual iPad**, for `tmp/compperf`. The compositor now
   caches up to 192 MB of layers plus scratch; on a 4000² canvas total GPU memory could reach
   ~450 MB. There is a memory-warning purge but it is unverified on device.
3. **Six shape questions** already put to the owner and unanswered: handle size; whether an oval's
   axis drag should no longer rotate; whether snap should work after the pen lifts; whether
   rectangles want mid-edge handles; whether an interrupted stroke should regain its hold window;
   and whether a stroke cut short by the app's own menu should keep its ink (it is discarded on
   purpose today, so a two-finger zoom mid-stroke cannot leave an un-undoable mark).

## Also gating `tmp/compperf`

**The XCUITest tier never completed** on that branch — two attempts, one killed by a concurrent
session, one stalled under contention. It changes the live canvas path, so that is a real gate.
Two test-hygiene traps it fixed are worth knowing: a persisted preference set by a test leaks through
`UserDefaults` into later tests *and the next run on the same simulator*, and four suites restored a
literal `.coreGraphics` in `tearDown`, which would have quietly switched later suites off the shipped
backend (hence `Compositor.defaultBackend`).

## Process — read this, it cost this session real time

- **Wrap every `xcodebuild` in `tools/simlock.sh`.** This Mac hit 1–3% idle with 5 concurrent runs,
  and contention does not just slow tests, it **returns wrong answers** — the same shape-hold test
  passed and failed on the same binary, and an agent nearly tuned a shipped constant against CPU
  starvation.
- **Launch agents in waves of two or three, not one per work item.** The lock bounds the machine, not
  the plan. The owner asked for this explicitly.
- **Agents park waiting on test runs without committing.** Read their worktree directly — `git log`,
  `git status`, the log file — rather than waiting for a resume round-trip. Tell them to commit
  before waiting; several left work loose.
- **Agents do not delete their simulators even when told to.** Sweep `xcrun simctl list devices`
  yourself. Keep `eraser-mutex-test`; delete anything else you did not create.
- The owner's behavioural theories are high-quality evidence and have twice beaten a code-tracing
  agent. When a report names a duration, grep for that number before theorising.

## Still open from BUGS.md, unrelated to this pass

Duplicating a cel/layer drops its interpolation recipe (needs a product call on UUID remapping);
Duplicate is a silent no-op against an adjacent neighbour; brush presets reset live size/opacity;
onion skin renders unmasked; a mask sourced from a graded group can be stale; the fill-tool
gap-closing UI test is still skipped. Also: a green backend-parity test does not prove both backends
ran — **that matters much more now that Metal is the default**, and it should be closed alongside
`tmp/compperf`.

## Close-out, when the above is merged

`git rebase origin/main` on `tmp/uxpass2`, `--ff-only` into main from the main worktree, remove every
`PaintApp-*` worktree and `tmp/*` branch, append one line to [SESSION_LOG.md](SESSION_LOG.md) and drop
the oldest so only five remain. Docs still need the prune CLAUDE.md asks for — `LAYER_COMPOSITING.md`
is 870 lines and the feature is done, and BUGS.md still lists the Adjust panel as "Coming soon" when
it was deleted this pass.
