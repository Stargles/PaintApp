# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — two things about measurement, before any feature

**1. ~~The test target cannot build in Release~~ — fixed 2026-09-05, and the "62x" that justified
the caveat turns out not to apply to the paths it was attached to.** `xcodebuild test -configuration
Release` builds and runs: **3177 total / 3174 passed / 0 failed / 3 skipped**, reconciled against a
static count of the selected classes.

**It was one line, and it was not pre-existing.** A single `@testable import PaintSoftware` in
`SampleRecordLogicTests.swift`, which `ENABLE_TESTABILITY` — a Debug-only setting — makes legal in
Debug and illegal in Release (*"module built without '-enable-testing'"*). It arrived at `96adbe8`
on 2026-09-04 05:56 with BRUSH.md §12 stage 4, about 26 hours before the handoff that called it
pre-existing; PERFORMANCE.md §11's Release simulator rows were taken at `912340a` and `eeefdee`
earlier that same night, which is the proof Release worked until then. **The import resolved
nothing** — every type that file names is compiled a second time into the test target, which is this
repo's documented convention (`BrushEngineLogicTests`' header) and the reason no other test file has
one. Deleting it changes no build setting, so the shipping binary is untouched.

**The interesting half is what Release then measured.** The 62x is real but it is a figure about
*Swift* code, and it was being applied to paths that are mostly CoreGraphics. MEASURED on an idle
machine, three samples each way, alternated, same warm device — see PERFORMANCE.md §12:

| `DabCostBench` | Debug | Release | Debug ÷ Release |
|---|---|---|---|
| the dab walk alone, no rasterization | 2.85 µs/dab | **0.115 µs/dab** | **~25x** |
| the same walk **with** rasterization | 6.40 µs/dab | 3.44 µs/dab | **1.86x** |
| a pad stroke (`PADREWALK`) | 43.7 ms | 43.1 ms | **1.01x** |

So **the pad re-walk figures were already right and the caveat on them was the error**: 18–44 ms is
what the artist pays, not a worst case sixty times too high. `BrushEditorModel.maximumStrokes` and
`BrushEditorLogicTests` both said the honest number "could not be taken"; both now carry the taken
one. **The rule to carry forward is that the Debug penalty is not one number** — it is ~25x on Swift,
~1x on framework work, and any given figure is a mixture. PERFORMANCE.md §7 argued exactly this from
first principles and can now cite a measurement.

**2. The full suite is green and the tree is verified.** MEASURED at `c26efc9` on an erased simulator:
**3363 tests, 3342 passed, 0 failed, 21 skipped, 36.5 min** — the third run in CLAUDE.md's history with no
environmental red at all, after a pass that rewrote the dab alpha, the modulation walk, the scatter output
and the whole library. The class table is re-taken in CLAUDE.md, and it carries a finding: **`BrushEditorUITests`
did not exist this morning and is now the suite's second-heaviest class at 516 s across 11 tests.** It is
the split candidate, and ~120 new tests cost +1,190 class-seconds, which ends the "a new test is close to
free" run that section had recorded five times — UI tests that drive a full-screen editor are not free.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**`main` is `c26efc9`. 89 commits this pass. Fast tier 3177 total / 3174 passed / 0 failed / 3 skipped.
No worktrees, no `tmp/*` branches, nothing uncommitted.**

**A Release build of `c26efc9` is on the owner's iPad, provisioning valid until 2026-09-12.** It carries
everything below.

## The brush engine is built — §12 stages 0 through 11 are DONE

[BRUSH.md](BRUSH.md) is the specification. **§2 is thirty-three owner rulings; read them rather than
re-deriving them.** Eleven were made this pass and four supersede earlier ones: §2.28 supersedes §2.22's
fixed shape, §2.29 supersedes §2.22's uncurved clause, §2.31 carves a deliberate exception out of §2.10,
and §2.32 supersedes §2.18's intrinsic draw.

**What shipped**: opacity and flow split with a per-stroke buffer; canvas-anchored texture; the brushes
menu with groups and the owner's two-tap navigation; the full-screen editor with orderable module chains,
noise octaves, second inputs carrying their own curves, typed values past 100% and a working Cancel;
relocatable storage; **twenty brushes in five groups, every asset generated, no third-party content at
all**; `density` as a threshold driven from the chain; and two-axis scatter oriented to the stroke.

**What is left of (37): §12 stage 12 only** — the `.abr` / Procreate `.brushset` / Clip Studio `.sut`
importers. The owner named those three and left the timing to me; it stayed last because the model moved
five times in one day and an adapter aimed at a moving target is written twice. **Stage 12 records what
is known about each container, to be verified rather than trusted.** Test files are a real dependency:
source freely-licensed samples first and only ask the owner for their Procreate packs if those are too
thin. **§8.3 is why this matters more than "last stage" sounds** — bought packs cannot ship inside the
binary, so the importer is the only lawful route to most of what exists.

## Ask the owner these

- **Their tuning pass.** Their Rough Ink is now the shipped one, pinned to within 0.76% of inked pixels.
  They have the build; ask them to go through the other nineteen. The loop they specified is tune,
  extract, done — `PaintSoftwareUITests/Fixtures/owner-tuned-library-2026-09-05.json` is how the last
  extraction was carried.
- **Blotchy and Bristle scatter ~53% wider on a fresh install than on their device.** §2.30 re-authored
  those two by hand and carried the number across rather than converting it. Deliberate, asserted, and
  written up in §13 — it wants their eye, not more arithmetic.
- **Drive a real Pencil and lean it over.** The simulator cannot synthesise pencil input, so **tilt has
  never been exercised by hardware** — two stages store and read it and nothing has confirmed the
  hardware end. Ten seconds closes a gap no test here can.
- **Splatter and Stipple want revisiting now that §2.30 exists.** Stage 11 shipped them as pictures
  because nothing could offset a dab *across* the path; two-axis scatter merged the same hour.

## What TODO (41) did and did not fix

**MEASURED, Debug, 2048x1024**: a cut's worst single render at 1,000 strokes went **608.8 → 225.8 ms**,
at 2,000 **1274.5 → 463.2 ms**; 2.1–3.5x fewer dabs. INFERRED on the owner's iPad 9, ~1.68 s → ~0.61 s.

**It is an order of magnitude short of the append's 105–832x and the reason is structural**: a cut's
damage is the footprint of *every* stroke it replaced, so the rectangle grows with density — 10% of the
canvas at 200 strokes, 25% at 2,000. The honest guarantee is *cost scales with the area touched*.

**The spike has moved to the main thread.** `resolveShare` went 13% → 31% at n=2000 because the render
half fell and the per-sample intersection search did not (237 ms worst; ~312 ms INFERRED on the iPad),
and unlike the render it does not run on `renderQueue`. **That is the next lever.** Only the two eraser
cuts declare `.region`; select-and-move, Clear and recolour still say `.everything`, and
`regionDamage(replacing:)` is the shared helper with no design left to do. **TODO (42) waits on
recolour.**

## Filed rather than fixed

- **[BUGS.md](BUGS.md) — the auto-resign daemon counts its own runs, not the profile's expiry.** It
  reported "3d remaining" on a profile that expired ten hours later, which is why the owner's app has
  died several times. **The obvious recovery fails**: rebuilding re-embeds the cached expired profile,
  so delete `~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision` first and check
  `ExpirationDate` *before* installing, since the build succeeds either way.
- **BUGS.md — a restored project texture can be held down by a negative cache entry.** Pre-existing;
  wants fixing with §13's document-opened-on-a-second-device case, which is the only way to reach it.
- **§13 — a repair that truncates a transparency layer differs from a full walk by 1–2/255** on pixels
  along the rectangle's edge. MEASURED as CoreGraphics rounding, non-accumulating, pinned three ways.

## Traps this pass paid for

- **Four of eleven tests in one branch were blind** — green against builds with the behaviour they name
  deleted. A fixture whose setup check was taken on the *uncut* list, a blend-mode test whose marks never
  overlapped, a "straddling stroke" that straddled nothing, and an undo test that rendered before the
  undo. **Mutation testing is what found them**, and one guarded the eraser-under-a-stack rule.
- **The triage recipe has an exception it did not know about.** CLAUDE.md's erase-then-re-run is right
  for a state flake and the **worst** case for a timing one: a wall-clock assertion read 43 ms warm and
  **207 ms after an erase**, so the prescribed confirmation failed 4.7x worse than the suite and read as
  a real regression. Wall-clock assertions now live in the bench files, which the fast tier excludes.
- **The simulator you are *driving* is a binary too** — `simctl install` ships whatever the last
  `xcodebuild` wrote, including a mutation run's build. One session diagnosed a defect that existed only
  in the installed bundle.
- **An assertion can be true of the world when written rather than of the thing it names.** A test called
  "the collections are disjoint" asserted a tip list was exactly `[.square]`; eleven shipped tips
  reddened it. It asserts the partition now.
- **A test written to catch a defect class can be broken and say so about itself** — the identifier
  census was red on `main` for hours because it named deleted presets.
- **Cross-branch collisions surface at the merge as compile errors, not before.** Four this pass: two
  enums grown independently, a preset deleted by one branch and named by another's new test, and a
  channel renamed by one and used by two others.
- **A green check is evidence about the tree that existed when you ran it.** A rebase output filtered to
  two lines hid a conflict and a suite was run on a half-rebased tree; separately, a result file was read
  because a notification arrived that belonged to a *different* task's stale wait.
