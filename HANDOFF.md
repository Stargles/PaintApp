# Handoff — 2026-08-18 (second pass, stopped at the weekly usage limit)

**Everything is committed and pushed. Nothing was lost.** Four branches were stopped mid-flight, and
three of them carry a `WIP …` commit made by the orchestrator, not by the agent that wrote the code:
**unreviewed, untested, possibly mid-edit. Read every hunk before trusting it.**

Read [CLAUDE.md](CLAUDE.md) first, then [TODO.md](TODO.md) — the owner's asks are live there and four of
them arrived during this pass.

## Pace — this is a standing instruction now, not a suggestion

**Two work streams at a time, maximum.** The owner set it after four workflows (~45 agents) launched
inside fifteen minutes consumed 40% of a five-hour window, and the weekly limit hit 98% shortly after.
TODO.md still says "three in flight"; **that line is about the Mac's cores and is now superseded** — the
usage window is the binding constraint, so "it needs no simulator" is no longer an exemption. Default to
a single scoped agent or to doing it inline; reserve a fan-out for work that genuinely needs breadth, and
say what it will cost before starting it.

## The four branches, in the order they are worth picking up

### `tmp/fillborder` — the only one that is clean, and closest to done
`02ea4d2` **Make the canvas border a wall the flood cannot cross, not a hint near ink**. No uncommitted
work. **Test status unknown — the run never happened.** Owner's ask: with padding increased, a line that
leaves the canvas, re-enters and leaves again should enclose a region against the canvas border, and today
the fill takes the whole page. The two suspected causes were that `setCanvasPadding` grows `canvasSize`
*itself* (`CanvasManager+Document.swift`), so the buffer edge is the outer margin while the border the
artist draws across is an inset rectangle nothing knew about; and that session 41 shipped the edge rule as
*conditional* on artwork being within the gap radius, so a long stretch of bare border was never a wall.
**Verify the commit against both before assuming it fixed the right one.** Start here: smallest, cleanest,
and it is a fill-engine change that will conflict with `tmp/lasso` if that lands first.

### `tmp/lasso` — real progress, then stopped mid-edit
`cc315f0` **Seed the lasso from the loop's ring, and keep what the collar could not reach** is the
specified algorithm going in. `2a6a7a7` is WIP on top, touching `LassoFillMask`, `MetalFillEngine`,
`CanvasManager+Fill`, `CanvasManager`, `CanvasView` and `SelectionOverlayView` — the breadth suggests the
§7 collar visualisation was being wired when it stopped. Below those, the two test-only commits from the
previous pass are untouched. [LASSO_FILL.md](LASSO_FILL.md) is the specification and the owner has ruled
on the semantics — **do not re-open the design.** The three traps are unchanged and all three are in the
spec: the loop must not be a literal wall (the flood enters the ring; the wall property comes from the
final intersect), `fillExpand` must be 0 in this mode, and there must be **no** connected-component filter.

### `tmp/menuinterrupt` — the largest finding of the pass, and the mechanism half-built
`8f30290` is [MENU_PRESENTATION_CENSUS.md](MENU_PRESENTATION_CENSUS.md) and it stands on its own — read it
before anything else in this area. **7 broken, 12 unverifiable, 44 safe, four distinct versions of one
bug.** `197885f` is WIP carrying three *new* files that are the mechanism taking shape —
`Engine/StrokeInterruption.swift`, `Models/CanvasPresentation.swift`,
`Views/CanvasPresentationModifier.swift` — plus edits to `CanvasManager`, `AnimationTimeline`,
`StrokeCanvasView`, `StrokeGestureRecognizer`, `CanvasView`, `EffectSection` and `LayerPanel`.
**Untested, and the design behind those three files was never reviewed** — the adversarial phase that was
meant to try to refute the root cause never ran.
The owner's requirement, in their words, is that this **not** be a third opt-in: the target is a
compile-time guarantee in the shape of `Tool.paintsOnCanvas` (exhaustive `switch`, no `default:`, over a
`CaseIterable` enum, plus a test asserting `allCases.count` against a hand-written table). **Say plainly
in the close-out whether that guarantee was achieved, or whether it came out weaker.**

### `tmp/crosseraser` — diagnosis ran, nothing is settled
Only `1d2ebdb`, the WIP commit. It touches `StrokeGeometry`, `VectorEraser`, `VectorLayer`, `Tool`,
`StrokeCanvasView`, `EraserSettingsPanel`, two logic-test files and `README.md`, so a design had clearly
been chosen — **but which one, and on what evidence, was never reported.** Re-derive it from the diff
rather than assuming. The standing hypothesis for the stub is in TODO.md and is unverified: crossings come
from `StrokeGeometry.intersections` at a width-aware tolerance, and `cutToIntersection`'s
`low = max(p)` / `high = min(p)` bracket may take a band edge rather than the centreline crossing, leaving
a stub about a half-width long.

## What the owner still owes an answer on, and what they owe a ruling on

Asked but unanswered:
- **Three Action Recorder captures** — timeline menu, onion panel, and a blend-mode `Menu`. The third is
  the one that matters most: **it decides whether the census's 12 UNKNOWNs are broken, i.e. 19 rather than
  7.** Nothing in the source settles whether a SwiftUI `Menu`'s outside-touch passes through to the canvas
  the way a `.popover` demonstrably does here. The alternative is an XCUITest in the shape of
  `CanvasTransformFreezeUITests`.
- Save semantics when a project loaded with something unreadable: overwrite, refuse, or prompt?
- Which faces belong in the font picker's favourites strip.

Carried, still unruled, both from the merged oval work:
- A double-traced ellipse detects as a **rectangle**. Pre-existing, verified, not a regression.
- The smart oval has no arc-end handles, so "I drew 100° and wanted 180°" means drawing it again.

## Where the stopped agents' findings are

The four workflow runs left transcripts and per-agent journals under
`~/.claude/projects/-Users-juliapark-Desktop-Kevin-P-PaintSoftware/f68ae64a-39e8-4348-934b-311f00faebdf/`:
`subagents/workflows/wf_8407cb2c-c78` (lasso), `wf_438cfc1d-3e4` (cross eraser), `wf_e022b0de-2b3`
(fill border), `wf_79b46a60-4eb` (menu interrupt); the scripts are under `workflows/scripts/`.
`journal.jsonl` in each holds what every agent actually returned, including the diagnosis phases whose
conclusions never reached a report. **Cheaper to read than to re-run** — but they are session-scoped, so
read them before that directory is pruned. Resume-from-run-id works only within the original session.

## Machine state

Four worktrees and four `tmp/*` branches, all pushed to origin. No stray simulator clones were created by
this pass beyond whatever the stopped test agents may have left — sweep with
`xcrun simctl --set ~/Library/Developer/XCTestDevices list devices` before the next run, and note that the
default device set never shows clones. `main` is at `c516eba` plus this handoff.

## Two process notes from this pass

- **`git merge --ff-only` from inside the branch's own worktree still says "Already up to date" and merges
  nothing.** The previous handoff warned about it; I did it anyway, in the same session I read the warning.
  Run merges from the main worktree, as their own command, with `git branch --show-current` in front.
- **`git -C <repo> worktree add ../PaintApp-x`** resolves the relative path against the repo, not the shell,
  so it lands *inside* the repo. Use an absolute path or `cd` first.
