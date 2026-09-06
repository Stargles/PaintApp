# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**`main` is `25e8e23`, pushed. Fast tier 3190 total / 3187 passed / 0 failed / 3 skipped, reconciled
against a static count of the 135 selected classes. No worktrees, no `tmp/*` branches, no simulator
clones, nothing uncommitted.**

**No full suite this pass.** Two commits, both narrow, both covered by the fast tier — but the vector
render path changed, so **the next session owes one**, and CLAUDE.md's class table is due a re-take with
it (`BrushEditorUITests` is the split candidate at 516 s across 11 tests).

**The iPad build is `c26efc9` and is now three commits stale.** Provisioning valid until 2026-09-12.
Neither of this pass's two changes is on it.

## Two things about measurement that are now settled, and change how you read every figure here

**1. The test target builds in Release again.** `xcodebuild test -configuration Release` runs: 3177 /
3174 passed / 0 failed / 3 skipped. One `@testable import PaintSoftware` in
`SampleRecordLogicTests.swift` was the whole of it — illegal in Release because `ENABLE_TESTABILITY` is
a Debug-only setting, and **resolving nothing**, since every type that file names is compiled a second
time into the test target (this repo's documented convention). Deleting it changed no build setting, so
the shipping binary is untouched. It was **not** pre-existing as the last handoff claimed: it arrived at
`96adbe8` about 26 hours earlier with BRUSH.md §12 stage 4, and PERFORMANCE.md §11's Release rows, taken
that same night, are the proof Release worked until then.

**2. "Debug is 62x slower than Release" is a fact about *Swift*, and it was being quoted at paths that
are mostly CoreGraphics.** MEASURED on an idle warm device, three samples each way, alternated — see
PERFORMANCE.md §12:

| `DabCostBench` | Debug | Release | ratio |
|---|---|---|---|
| the dab walk alone, no rasterization | 2.85 µs/dab | **0.115** | **~25x** |
| the same walk **with** rasterization | 6.40 | 3.44 | **1.86x** |
| a brush-pad stroke | 43.7 ms | 43.1 | **1.01x** |

**The pad re-walk figures were already the artist's number and the caveat on them was the error** — 18–44
ms, not a worst case sixty times too high. Two comments said the honest number "could not be taken"; both
now carry it. **Carry the rule forward: the Debug penalty is not one number**, it is ~25x on Swift and ~1x
on framework work, and any given figure is a mixture. Say which when you write one down.

## What shipped this pass

**TODO (41)'s second half — undo and redo of an eraser cut cost the rectangle rather than the cel.** The
owner, on the build §11.10 measured: *"right now, erasing in a vector layer with a lot of strokes is
relatively good, but undo and redo causes some lag."* The cut had its rectangle; its **undo** went through
`elements = snapshot` + `bumpVersion()`, which declares `.everything`, so one press paid the whole-cel
re-walk the cut had just avoided.

`VectorCanvas.restoreElements(_:changedInk:)` is the seam now. **One rectangle serves both directions**,
because it bounds every pixel where the two lists differ and that reads the same way forwards and
backwards; `StrokeCanvasView.foldGestureDamage` accumulates it from what the gesture's own edits declared.
**The half the caller cannot bound is measured rather than declared** — what *departs* is still in the
list with its footprint measured — which is why an undone append is cheap with no rectangle from anybody.

MEASURED, both arms alternating in one process on an idle machine, Debug, 2048x1024: **1.6–4.8x fewer
dabs, 1.8–6.7x less wall clock**; an undo press at 2,000 strokes 1,709.9 → **919.6 ms**. Plainly: **half,
not an order of magnitude**, and the prize shrinks with density for §11.10's reason — the rectangle is
3.5% of the canvas at 200 strokes and a third of it at 2,000. PERFORMANCE.md §11.11.

**The re-walk is off the main thread**, so what the artist was experiencing is not a freeze but the old
picture standing there for that long before the ink comes back. That does not change the fix; it changes
how you reproduce it.

## Ask the owner these

- **Which eraser mode was the report about?** It decides whether anything is left of it. The two *cut*
  modes are cheap in both directions now. **Mode 1 — the eraser-that-is-a-stroke — appends, so its undo
  is cheap and its redo still pays the full walk**, and that limit is inherent rather than unfinished:
  the ink coming back has never been drawn on that canvas, so no footprint exists for it, and BRUSH.md
  §12 stage 8 refuted deriving a box from the brush (`ResponseCurve` does not clamp). Fixing it needs a
  new mechanism — a one-round-trip memory of what a restore vacated — which is worth building **only if
  they are actually using Mode 1**.
- **The importer is dropped for now, by the owner, this pass**: *"skip the importer for now."* BRUSH.md
  §12 stage 12 stands unbuilt and its survey is still the right way to start it.
- **§13's three open brush questions were offered and declined** (*"Nothing go build"*): Splatter and
  Stipple re-rendered with §2.30's scatter, Blotchy and Bristle's 53% divergence, and whether eight noise
  octaves is the right cap. All three want their eye rather than more arithmetic, so they keep.
- **Their tuning pass.** Their Rough Ink is the shipped one, pinned to within 0.76% of inked pixels; the
  other nineteen have not been through their hands. The loop is tune, extract, done —
  `PaintSoftwareUITests/Fixtures/owner-tuned-library-2026-09-05.json` is how the last extraction went.
- **Drive a real Pencil and lean it over.** The simulator cannot synthesise pencil input, so **tilt has
  never been exercised by hardware** — two stages store and read it and nothing has confirmed the
  hardware end. Ten seconds closes a gap no test here can.

## What is next, and none of it is chosen

The brush engine has nothing actionable left with stage 12 dropped. Ready to start, in no order:

- **(29) stage 7** — the rest of the memory audit. Stages 0–6 are merged, export included.
- **(39)** — three timeline defects, all reported from the device.
- **(40)** — onion skin z-order, and what Behind should mean.
- **(41)'s remainder** — select-and-move, Clear and recolour still say `.everything`, and so does
  `registerVectorElementsUndo` (the fill/text/Clear counterpart of the seam this pass built, which can
  adopt it as soon as those sites can name their own rectangle). **TODO (42) waits on recolour.**
- **The main-thread spike §11.10 left behind** — `resolveShare` at 31% of a To Cross drag at n=2000,
  ~237 ms worst, and unlike the render it does not run on `renderQueue`. Untouched this pass.

## Filed rather than fixed

- **[BUGS.md](BUGS.md) — the auto-resign daemon counts its own runs, not the profile's expiry.** It
  reported "3d remaining" on a profile that expired ten hours later, which is why the owner's app has
  died several times. **The obvious recovery fails**: rebuilding re-embeds the cached expired profile,
  so delete `~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision` first and check
  `ExpirationDate` *before* installing, since the build succeeds either way.
- **BUGS.md — a restored project texture can be held down by a negative cache entry.** Pre-existing;
  wants fixing with §13's document-opened-on-a-second-device case, which is the only way to reach it.
- **A repair that truncates a transparency layer differs from a full walk by 1–2/255** on pixels along
  the rectangle's edge. MEASURED as CoreGraphics rounding, non-accumulating, pinned three ways.
- **`ONLY_ACTIVE_ARCH` is Debug-only**, so a Release *test* run compiles arm64 and x86_64 both. Pass it
  on the command line if build time matters; do not put it in the project, where it also reaches the
  device build.

## Traps this pass paid for

- **A mutation sweep found three things reading could not**, and all three were in code and tests that
  had already been read carefully. The union of the vacated and the declared rectangle looks redundant on
  a single split and is not, because `departing` is a union over the *whole gesture* and a stroke deleted
  outright leaves no piece to bound it. `testACutMintsFreshIdsRatherThanRewritingInPlace` did not redden
  its own stated mutation — the grid's marks are shorter than the eraser nib, so its cut *deleted* rather
  than split and its "survivors" were the marks nobody touched, equal under any implementation. And
  `dropIncrementalBase()` in the new seam was dead on arrival. **Re-run the sweep after adding a test,
  not only after writing one**: two of these surfaced only on the second sweep.
- **A bench harness can be a no-op for the path it is measuring.** `medianSeconds(runs: 3)` repeats one
  restore three times — right for `bumpVersion()`, where every run is the same full walk, and wrong for
  the region path, where the second identical restore has nothing arriving and nothing departing and
  falls through to a full walk. The median of three would have reported **no improvement at all**.
  Alternating undo and redo is both correct and what the artist does.
- **A one-line diagnosis in this file went unchecked for a day and was wrong in the useful direction.**
  "Pre-existing `@testable import` module error" was neither pre-existing nor in need of a build-setting
  change, and finding out which cost less than the caveats it had been generating.
- **A green check is evidence about the tree that existed when you ran it**, which a rebase invalidates.
  This pass's fast tier was re-run on the rebased bytes before the merge, and CLAUDE.md's warning about a
  filtered rebase output hiding a conflict is why.
- **`SendMessage` can be unavailable**, so a running agent cannot be corrected mid-flight. Put everything
  a worker needs in the brief; if a finding lands while it is running, plan to reconcile at the merge.
