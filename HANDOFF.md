# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks **in queue order — the top of the list is what to do next**;
[BUGS.md](BUGS.md) is what we find.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**No branches, no worktrees, stash empty, no simulator debris.** Session 40 closed at `d2205d5`,
71 commits, everything merged and pushed.

**Fast tier: 3761 total / 3758 passed / 0 failed / 3 skipped, Debug *and* Release**, reconciled
against a static `func test` count at every step.

**Full suite at `d2205d5`: 4034 total / 3977 passed / 3 failed / 54 skipped.** All three passed clean
in isolation. **Nine full suites ran this session** and every one is recorded in git log; the class
table in CLAUDE.md is current as of `b79f879`.

**The owner's iPad has `main` on it** (Release, installed 2026-09-10) and has not reported back on it.
Ten artist-facing features landed in that build — see "What shipped" — so **the first thing worth doing
next session is asking what they found**, rather than starting a new item cold.

## The one thing to read before trusting a red test

**The failing set has been different on every full run of this session** — 8, then 3, then 2, then 3,
with almost no overlap — and every failure passed in isolation. CLAUDE.md now states the rule this
taught: **a regression fails the same tests twice.** Two runs of the same bytes that disagree about
*which* tests fail mean the run is the variable, whatever the assertion messages say. The old rule
("a cluster with no assertion messages") did **not** fire: five failures once read as one coherent
eraser regression, with messages, in a branch that had just changed a panel's layout. None reproduced.

Rule out the cheap causes first (disk, clone debris, `Restarting after unexpected exit` in the log, a
stray booted device), then **re-run whole on a freshly created device** before reading a list as a
finding. The fresh device is a partial cure as well as a control — eight failures became three on the
same commit.

**Four flakes are filed in BUGS.md**, three pre-existing and one fixed. **Two of them are *logic*
tests, which the fast tier does run** — so the tier is not blind to them by selection; it is blind
because they only fail under the contention a full suite creates. **A green fast tier is not evidence
that a logic test is deterministic.**

## What shipped this pass

**Three items closed and deleted whole**: (57) the on-disk project layout, (36) the chosen folder, and
(56) the per-edit cost — the last closed by the owner rather than a measurement (*"35ms is great at
least for now"*).

**Performance, all MEASURED on the owner's iPad in Release.** Per-edit main-thread busy **115.4 →
35.7 ms** at forty strokes a cel, and forty strokes now cost *less* per edit than one. The debounce-
window stall the owner called "the second flicker" went **29 of 36 operations → 0 of 72**. Undo of a
fill is **12x** faster (1071.9 → 89.5 ms at 2,000 strokes). Two renderers left the main thread: the cel
thumbnail (the fifth, and the last one there) and the onion skin during playback.

**Keyframes**: layer *and* folder opacity are keyframable through the first non-pose channel kind
(`TargetChannel`); animation-group membership is three operations (add, remove, move) under the owner's
"stays where it looks on screen" ruling; folders can place a keyframe from their options panel; and the
take recorder has all three surfaces — slider, Move box and **canvas**, where a stroke drawn while a
take runs is cut at cel boundaries.

**The recorder arms and starts in two acts**, per the owner: record turns blue and nothing moves, and
the take begins when the pencil lands.

**The disappearing strokes are CLOSED.** `UnlandedInk` holds a finished stroke's display image until a
base containing it lands. Neither of BUGS.md's two options was taken: nothing composites on the main
thread, and the held ink is **2.6 MiB at any canvas size** — *less* than the `StrokeScratch` the shipped
code held for the same window.

**Docs**: CLAUDE.md 1103 → ~800 lines (fourteen dated class tables became eleven conclusions), memory
36 → 33 files, and (45)'s spec sweep checked **314 numbered anchors** and found ~130 displaced plus
nine places the code had moved out from under a spec's own claim.

## Start here

**Ask the owner what they found on their iPad first.** Then, in queue order:

**(60)** is the biggest of the small work: bloom colour and Sobel gain, plus four new effects the owner
added on 2026-09-10 — a computer-screen look, hue colorize, dither, and **recolour**, whose design is
already settled in the item (Oklab tolerance, softness, first-match-wins, shading preserved) along with
its eyedropper, whose *from* colour must sample **under** the effect rather than off the screen. Two of
the four may not be new effects at all; the item says which and why.

**(61) wants a design document and a conversation, not a branch.** The transform layer becoming its own
type with five modes — and the five are not one shape: parallax, rotate and screen shake are poses,
repeat is a timeline operation, and duplicate offset is a compositing one. The owner spotted the last
themselves and prefers it as a value-layer effect. **The spec's first job is to say how many homes these
want**, with *"do whatever is cleanest"* as the owner's own instruction.

**(62)** is settled and small: keys outside a cel's span are cropped, as one undo step that says what it
discarded.

After those: **(41)**'s two remaining boxes (a rewrite in place needs a hook at the mutation site, before
it overwrites — that is the shape, not yet built), **(21)**'s folder graph band and stage 6, then (42),
(22), (10), (37), (45)'s remainder.

## Waiting on the owner

- **What they found on the device.** Nothing else here is blocked.
- **(61)'s design conversation**, before any of it is built.
- **(21) animation-group retagging** is no longer waiting — ruled 2026-09-10 and shipped.
- **Two interpretations they should sanity-check**, both recorded in the items and both mine rather than
  theirs: that "stays where it looks on screen" means *at the frame you are on* (every frame is not
  expressible — only groups carry tracks), and that a hidden scale/skew channel **carrying a curve**
  stays visible so an animation cannot be lost behind a default.
- **(22)** and **(10)** deprioritised; **(37)**'s importer dropped.
- **BUGS.md's five remaining `.popover`s** have the timeline's swallow-every-drag defect. Three are
  colour pickers whose chrome would visibly change — the owner's call.
- **XCUITest cannot synthesise a Pencil**, and three things now rest on that: the pen half of the graph
  editor's box-select, pressure across a stage-10 cel seam, and the pencil half of (47). **The owner has
  granted device build and deploy**, so these are now checkable on the iPad rather than unprovable.
