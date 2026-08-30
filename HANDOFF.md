# Handoff — 2026-08-30 (session 78)

<!-- This file is BOTH the state of the repo and the prompt that starts the next session. It was once
two files and they drifted apart inside a day, because the same state had to be written twice. Keep it
one file. Rewrite the paste block when you close a pass; do not append to it. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md, KEYFRAMES.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline. `main` is `7c38ba2`. **Fast tier 2227 / 2224 / 0 / 3.** **No full suite was run this pass**,
and two heavy classes were split during it, so **CLAUDE.md's 22.3 min is stale in the *optimistic*
direction** — the ~15-16 min the arithmetic predicts is labelled INFERRED there and nobody has watched
a run since. **Take a real full run early**, on a freshly erased simulator, under `tools/simlock.sh`:
it is the only way to learn what the two splits bought, and every later measurement is read against it.
No branches, one worktree, clean tree.

**1. The graph editor is built — D1 through D4 — and nothing about it is left that the owner asked
   for.** KEYFRAMES §11 is the record: D1 row geometry, D2 the band, D3 the gestures (drag a key on
   both axes, tap to add and remove, a marquee that picks up a set which then travels as one body),
   D4 the channel list as a *filter*. All six of the owner's asks from §2.26's message are merged, so
   TODO (22) is down to one line.
   **The scope ruling is theirs and is not in question**: *"graphs are layer based, so tapping on
   another layer should just open the other layer's graph."* One band at a time, under the selected
   layer — which is also the cheapest thing to key, an `Int?` rather than a set.
   **What is genuinely left, and none of it is an owner ask**: bezier tangent handles (the model
   already carries `inHandle`/`outHandle` and five tangent modes — what is missing is a second hit
   target per key and the arbitration against grabbing the key itself, so it is a stage, not an
   afternoon); ask 6's *cel* marquee, which the owner themselves put in the future and whose stub is
   "Select Multiple", `.disabled(true)`; and one loose end D3 handed to D4 after D4 had already
   merged — tapping away a channel's second-to-last key makes it stop satisfying `isAnimated`, so the
   whole curve leaves the band mid-gesture. It wants a listed-but-flat state or a note in the channel
   list (KEYFRAMES §11.4, "One thing found and left").

**2. TODO (10) is the next buildable thing and its route is already decided — do not re-derive it.**
   The owner ruled, having been shown the A/B: *"toggle option between OKlab and normal… You decide
   the best route for the oklab."* The route is in TODO (10) and the evidence is
   [LINEAR_LIGHT_AB.md](LINEAR_LIGHT_AB.md) with five rendered PNGs under `docs/linear-light-ab/`.
   **The switch's two positions are sRGB and *linear light*, not Oklab**, stored as an extensible enum
   so Oklab can be a third; the muddy middle is a gamma artefact, worst case MEASURED 73/255. Oklab
   still gets built, for *interpolation*, where it is per-colour and outside the parity gate.
   **The scope is three coverage sites and the compositor is the one the artist does not paint on** —
   every dab is a `CGGradient` into an 8-bit DeviceRGB bitmap — so a compositor-only version leaves
   the dark ring in place whenever both hues are on one layer, and is not worth shipping.
   **Two things are unruled on purpose and one of them needs the owner**: how the result comes back
   *out* of linear (a `pow` on both backends, or an 8-bit-linear quantization that bands the shadows),
   and what linearizing does to the meaning of Hue/Saturation/Color/Luminosity, whose luminance
   coefficients are specified on non-linear values.

**3. Also open, unchanged: TODO (23)** — the owner's explicitly-not-priority ask that selection
   membership move from Move to Select so Recolour can use it — and **KEYFRAMES §8 stage 4** onward,
   the rest-space dab bake. **Distort is stage 5b now**, not last: it needs the transform channel and
   nothing else, the schedule was delegated and that is the call. Stage numbers 6-10 were left alone,
   so there is deliberately no stage 9.

**4. The traps this pass paid for, all five of them about *evidence* rather than about code.**
   - **A comment can be true where it was written and false where it was pasted.** D3's tap-vs-drag
     predicate came from `CurveEditor` with a comment explaining why `didMove` "would be the wrong
     question" — true there, where the flag is set only after a handle is grabbed; false here, where
     the marquee sets it too. A drag that changed its mind **deleted the key it was carrying, with no
     undo step at all**. Read a borrowed comment against the code you pasted it into.
   - **A judgement made by looking at one example generalises silently.** D2 put the playhead in front
     of the band "having looked at it" and recorded that a saturated curve reads through the wash.
     True of the hue it was looked at; three of the palette's eight are washed to grey, and only a
     screenshot found it.
   - **Looking at the feature found three things 2,224 passing tests structurally cannot** — a colour,
     a `CGContext` and a layout that runs off the panel. They are in BUGS.md. **This suite has no tier
     that can see a rendered pixel**, so when a feature is visual, budget a look at it.
   - **A worker's completion notification is the only signal its tree is finished.** A worktree was
     branched this pass from a commit whose agent had not reported, and was re-based off the last
     reported-complete commit instead.
   - **Mutation-test your own tests, and a proximity test proves nothing until its fixture holds two
     candidates.** D3 found one of its own tests could not fail: the fixture put two dots 80 pt apart,
     so "nearest" and "first" were the same answer. Two independent reviews then found the same class
     of defect again, one level down.

**5. One process note about talking to the owner.** Asked where the graph editor should open, they
   answered the question and then said *"I'm missing context. What is a graph band?"* — **"band" was
   our invented word and the question was unanswerable until it was defined with a picture.** Define
   invented vocabulary, or better, render it; they judge behaviour, not internals.

**Do not re-litigate**: KEYFRAMES §2's twenty-eight rulings and §11.6's three; LASSO_MOVE §5's
twenty-five; CANVAS_RESIZE §5 and §6; EFFECT_BACKDROP §5 and §2.1; (10)'s sRGB/linear-light route.
```

---

## State

`main` = `7c38ba2`, 21 commits above `0513d06`. **Fast tier 2227 total / 2224 passed / 0 failed / 3
skipped**, up from 2153 at the start of the pass.

**NO FULL SUITE WAS RUN.** CLAUDE.md's 22.3 min figure predates both of this pass's class splits and is
therefore stale in the direction that flatters us. The arithmetic there — ~3,542 class-seconds over four
clones against a new 327 s floor, landing nearer 15-16 min — is labelled INFERRED, and it should stay
INFERRED until somebody watches a run.

**Two heavy classes were split, both on measured seconds rather than on test count.**
`LayerPanelUITests`, 515 s across 19 tests and the whole suite's floor, became
`LayerFolderAndMaskMenuUITests` (190 s / 7), `LayerPanelControlsUITests` (174 / 7) and
`LayerStackUITests` (159 / 5) — same file, every test body byte-identical, 523 s against 534 s for the
same nineteen immediately before the cut. `SelectionAndMoveUITests` at 327 s is the new floor. And `GraphEditorUITests`, which this pass grew
from ~40 s to a MEASURED 271 s and the suite's second-longest class, split into `GraphEditorUITests`
(7 / 133) and `GraphEditorGestureUITests` (3 / 136).

A Release build of `7c38ba2` was being installed on the iPad as this was written; the last build
*confirmed* on the device is `a85a316`. Ask the owner rather than assuming.

## What landed

**The graph editor, stages D2 through D4, each adversarially reviewed and each review real.**

- **`5297c35`** — the owner's three rulings and one delegation, plus the y-axis question answered from
  a note already in the tree (`Effect.swift`: draw over `uiRange`, key anywhere in `modelDomain`).
- **`931b859`** — D2, the band. `Views/TimelineGraphBand.swift` holds every number; `TimelineLayoutKey`
  gains the whole band as one field, because a curve's *shape* moves nothing else on the track.
- **`b3ec305`** — D2's review: five findings, five real. The band sampled the whole track (a dirty rect
  is not a clip), a keyframe could not be placed at a frame with no cel, the drop strip and the drag
  ghost disagreed by 96 pt, a key's dot is off the line above step 1 and is meant to be, and **one test
  that could not fail** and asserted only that `make` is deterministic.
- **`327374b` / `b204dd6`** — the reflow the band causes, which is the scope ruling's own cost. A block
  drag was resolving the drop against moved rows, so **a re-time silently became a cross-layer move**;
  the band is pinned to its row for the length of that one gesture. The two-stage tap is **not** fixable
  and that is the answer: one wasted tap per layer switch, paid once. Scroll compensation was what the
  owner was told the fix would be, and it does not work — the reflow is not a uniform translation.
- **`bf423f0` / `f543a71` / `1ce12f8`** — D4, the channel list. It is a **filter**, applied inside
  `graphBandContent` *before* the layout key is built, because applied later it would change what the
  band should draw without moving the key. The review deleted a chevron whose collapse state was keyed
  by effect case and scoped to no band, took `Channel.groupName` out of the layout key (`.blur` answers
  two display names off a toggle, so one tap on Directional relaid out the whole timeline), and killed
  three more assertions that could not fail.
- **`56b0479` / `bccbfc2`** — D3, both halves. A key is **stopped** by its neighbour rather than
  consuming it; a drag clamps to `modelDomain` and never to `uiRange`, with hit-testing on a clamped y
  so an out-of-range key stays grabbable; one drag is one press of Undo. The marquee's group takes one
  frame delta clamped by its tightest member, shares a vertical travel in **points** because each
  channel normalises its own axis, and removes every carried key before inserting any.
- **`4ea6722` / `dbbe775`** — D3's review. The tap-vs-drag predicate, the unrecoverable delete it
  allowed, and the fixture that could not tell "nearest" from "first".
- **`7c38ba2`** — the band moves above the playhead, reversing §11.3's fourth decision. Verified by two
  screenshots of one fixture, which is the only way it could have been verified.
- **`e1c002f` / `8507bdc`** — six screenshots under `docs/graph-editor/`, and the three defects looking
  at them found.

**The colour switch.** `1fd6e23` renders the A/B — five labelled PNGs, a generator, no simulator — and
`f396aaa` records the owner's ruling and the route it delegated. Worst 8-bit channel difference **73/255**,
exhaustive over every (backdrop, source, coverage) triple for Normal.

**The cost model.** `7c806b5` split `LayerPanelUITests` after measuring per-test seconds first;
`4408fd3` fixed a doc comment that named that class as the suite's floor and went stale the same day.

**BUGS.md** gained the popover that re-presents itself when its host returns, the arithmetic on
`draw(_:)` views as wide as the whole document, and the three the screenshots found.

## What this pass learned that outlives it

- **A borrowed comment carries its premise, and the premise does not travel.** `CurveEditor`'s `didMove`
  sentence was true in `CurveEditor` and false one file over, and the difference was a single extra
  assignment in the pasting site. The predicate is now `TimelineGraphBand.isTap`, where the fast tier
  can read it — `TimelineTrackView.swift` is not compiled into the test target, which is exactly why a
  rule this load-bearing went a whole stage with nothing naming it.
- **"Having looked at it" is a sample size of one.** Both this pass's visual decisions were made that
  way; one of them was wrong for three hues in eight, and which channel gets which hue is only its
  position in `Effect.parameters`.
- **A test that catches a defect *sometimes* is worse than one that never does.** `applying` walks its
  keys sorted now — which changes no answer it gives — because the unsorted version killed its mutation
  five runs in six, off Swift's per-process `Dictionary` hash seed. This repo triages a one-off red as
  environmental until an isolated re-run says otherwise, so an intermittent test spends that judgement
  for everyone.
- **A proximity test proves nothing until its fixture holds two candidates.** Three occurrences, three
  levels: §11.3 found it, D3's five-mutation pass found it again for `nearestKey`, and the review found
  it a third time one level down in `nearestChannel`.
- **Split on seconds, never on tests.** `GraphEditorUITests` is 7/3 and not 5/5 because each gesture
  test spends ~45 s and nearly all of it is authoring an animated curve — the graph editor edits curves
  and cannot be the thing that makes the first one. A count-balanced split would have left 3 s on one
  side and 268 on the other.
- **A class grows past the floor while nobody is looking.** `GraphEditorUITests` went ~40 s → 271 s
  across three stages, none of which was a suspicious commit, and became the suite's second-longest
  class without anyone deciding to make it so.

## Still open

TODO (10) — the colour switch, route decided and unbuilt, with two questions unruled inside it. TODO
(23) — selection membership moves from Move to Select, the owner's not-priority ask. TODO (22) is now
one line: ask 6's *cel* marquee, which the owner put in the future themselves.

KEYFRAMES §8 stage 4 onward. §9's four open questions. §11 has no ruled-open items left — §11.6's three
are all answered — but three things sit outside it: bezier tangent handles, the cel marquee, and the
channel that vanishes when its second-to-last key is tapped away.

`ARCHITECTURE_REVIEW.md` findings 2-4. BUGS.md carries the three the screenshots found, the popover
that re-presents itself, the track's `draw(_:)` view widths, the interactive-gesture CPU composites,
Fill/Clear on a derived in-between, the raster-storage bound, the unclamped zoom,
`TextFrame.homography` decoding with no validity check, PERFORMANCE item 14, the narrowed mask-cache
structural gap, and the folder-row accessibility gap.

Two behaviour questions are still owed: save semantics when a project loaded with something unreadable,
and which faces belong in the font picker's favourites strip.

**Found and deliberately not fixed this pass**: the band's backing store is `totalWidth × 96` and the
largest single store on the track, left because *every* view on the track is `totalWidth` wide and the
fix belongs to the track; colour, toggle and picker rows still write a whole resolved `Effect`; stepped
and compound parameters still cannot be keyed; and six of the thirteen effects never match an XCUITest
query, which is almost certainly a scrollable-menu accessibility limit and will read as a broken app to
whoever reaches for one next.
