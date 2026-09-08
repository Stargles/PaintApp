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

**No branches, no worktrees, no quarantine, stash empty, no simulator debris.** 55 commits this pass.

**Fast tier: 3516 total / 3513 passed / 0 failed / 3 skipped**, Debug *and* Release, reconciled exactly
against **3516 static `func test` declarations across 152 fast-tier files**. A naive
`grep -c "func test"` over-reads by exactly 3 — three `private static func testBrush()` helpers, in
`VectorTextPersistenceLogicTests`, `VectorCanvasDataLogicTests` and `TextHitTestLogicTests`.

**Full suite MEASURED at `55b4a63` on an idle machine with a freshly erased device: 3749 tests, 3709
passed, 4 failed, 36 skipped, 36 min.** One failure is a wall-clock assertion under parallel clones
(`PerfBaselineTests.testTheLayeredLiveStrokePreviewCostsWhatTheRasterPathCosts`, 0.0165 s against a
0.0152 s cap) and passed clean in isolation. **The other three are real** — see below. CLAUDE.md
carries the class table from the previous run.

## The three regressions the full suite found are fixed, and they were not what they looked like

**They were not a persistence defect. No persistence code ran.** All three stopped ~20 s in, on the
same assertion — `XCTAssertTrue(galleryButton.waitForExistence(timeout: 5))` — because `ed7c8f4` added
an explicit `.accessibilityIdentifier("toolbar.galleryButton")` to `TopToolbar`, and **an explicit
identifier replaces the implicit one SwiftUI derives from `Image(systemName:)`**. So
`app.buttons["square.grid.2x2"]`, which two older helpers used, matched nothing. The author of that
line wrote a new suite against the new identifier and never saw the two existing call sites.

**What the reds actually meant is worth more than the bug.** From `ed7c8f4` until this fix, nobody had
exercised save→relaunch→load, corruption auto-restore, or delete→trash→restore end to end. The
verification run is the first time those assertions executed against post-(36) code — and a mutation
that orphans the vector payload on save makes all three run their full journeys and fail at their
*content* assertions, which proves they still guard data loss rather than merely finding a button.

`tools/check-ui-identifiers.py` is the guard: sub-second, exit 1 on any UI-test lookup by SF Symbol
glyph name, 1 finding against the pre-fix tree and 0 after. **The general "does this identifier exist"
version was tried and abandoned at 186 false positives**, and the tool's docstring says so, so nobody
retries it.

**Still unverified, and honestly so**: no UI test drives recovery of a project *inside a folder* —
`simulateNewestProjectCorruption` walks one level — though the shipped repair, snapshot and sweep passes
are tree-aware and `ProjectFolderLogicTests` covers nested cases at the model level. Migration against a
real security-scoped folder is untested anywhere, as is `-resetGallery` on a device that has adopted one.

**The structural lesson stands.** These are XCUITests, and **the fast tier selects only logic suites by
filename** — so a branch can be green in Debug *and* Release and still ship this. That is the **second**
time in one pass a defect lived in that blind spot; the first was `RecordingUITests` after stage 7.
**A branch being green in both tiers is not evidence about any XCUITest.**

## Start here

**(41), then (42) — the owner set that order on 2026-09-07.** It is the top of the queue and the only
large item that needs no conversation first.

**(41)'s remainder is a design problem, not an optimisation, and this repo has been wrong about that
twice.** The item's own text records that *"there is no design left to do"* was wrong on two separate
occasions. The hard part: an element that keeps its id through a rewrite — Recolour, Apply Brush, a
text re-edit, every lasso-move nudge — has **no rectangle any caller can supply** that says which
footprint stopped being true. Bounding it needs an idea, not a tighter caller. **Brief it as a written
proposal reviewed before a line is edited**, rather than letting an agent improvise in the render path.
(42) is blocked on it: a live preview over a selection is exactly that rewrite-in-place case.

After that, in queue order: **(21)**'s stage 10 and its two conversations, then **(45)**'s three open
boxes — eleven spec documents are still unswept for citation rot.

## What shipped this pass

**(53)** the 8 fps keyframed-playback stall · **(51)** onion-skin opacity · **(52)** refuted, already
fixed · **(47)** the pen-only finger tap · **(12)** animated Distort · **(26)** import videos · **(31)**
the canvas cap · **(36)** chosen-folder storage · **(54)** the held-frame recomposite · stage 7's
editable fps and take recorder · and a large slice of **(45)**.

- **(53)**: `sandwichEngagesOnCanvas` engages on a container pose, so a keyframed move serves the baked
  frame instead of rasterizing posed ink once a tick — **72.8 ms → 3.31 ms a frame**, MEASURED in
  Release on an idle machine. A **cel's own** pose channel has the identical defect at 73.6 ms and is
  deliberately open in BUGS.md: engaging there would make a drag show a stale composite, and nobody has
  measured that drag.
- **(54)**: the owner said *"the bake **and** cache"* and was right about the cache. The bake already
  deduped a hold to **one** composite; the live canvas did not, because `SandwichKey` carried `frame`.
  MEASURED on a seed whose first four frames move and last seven hold: **5 → 12 rebuilds before, 5 → 5
  after**, moving frames unchanged as a control. What the owner saw on the *bake* side, where nothing
  was wrong, is the amber bar clearing one frame at a time because the loop still visits every held
  frame.
- **(31)**: `maxCanvasExtent` is **6000**, MEASURED on the owner's iPad — a fresh document survived
  12000 and died at 13000, a worked one survived 11000, ceiling 1850 MiB. **At 16383 the footprint is
  flat through the whole gesture and explodes 6.6 s after pen-up**, so the dabs are cheap and the
  commit is what kills it. The arithmetic it replaced was 2.7x too pessimistic on a fresh document and
  within 6% on a worked one.
- **(36)** was fast-tracked because **a measurement pass wiped the owner's iPad container** on
  2026-09-07, destroying their `AnimationTest` document with no recovery. `-resetGallery` did it, from
  a Release build on a physical device. It is refused off the simulator now **and** forgets the
  chosen-folder bookmark before wiping, because it resolves its directories through `ProjectLocation`
  and would otherwise reach outside the container entirely. **Treat the owner's 2026-08-27 "everything
  on the ipad is expendable" as lapsed** — they are keeping real work there now.

## What this pass paid for

**Subagents spawned subagents.** Three briefed agents became **seven running**, because
`general-purpose` carries the Agent tool and no brief forbade delegating. With the cap misread as "1
Opus **plus** 2 Sonnet" when it is **1 Opus *or* 2 Sonnet**, this burned millions of tokens, hit the
usage limit and killed five agents mid-task, creating a three-branch quarantine that took a session to
clear. **Every brief must say: do not spawn subagents**, and **call `ListAgents` and confirm zero
running before every launch** — a `completed` notification does not mean an agent is finished. One
resumed an hour later and two Opus agents ended up in the same worktree; the second refused to act on
the first's uncommitted tree, which is the only reason it did no damage.

**Every audit of that quarantine found something no diff review would have.** A test whose pixel probe
fired at frame 0, where the pose *is* rest, so it agreed under any implementation whatever. A bench
whose `tearDown` trapped on the skip path and **red every full suite**. A frame rate that could change
under a running take. All found by mutating each assertion, none by reading.

**The disk filled to 186 MB free**, because every killed agent left a ~3.5 GB simulator device and
thirteen accumulated. **Create a device, delete it immediately after the run that needed it** — not at
the end of the task. 58 GB of the owner's old screen recordings are archived on their external drive at
`/Volumes/ST Julia/Archive/ScreenRecordings`.

## Waiting on the owner

- **(21) stage 7's other half.** §5 asks for one mechanism on two surfaces and only the slider is built.
  The Move box needs rulings on resampling and tolerance for a **quad**, which `ValueRecording` cannot
  express; §5's slow-motion multiplier is unbuilt for the same reason. **Stage 10 sits on a whole stage
  7.** Also worth their eyes: at 24 fps a take on a *new* document is over before a person can react,
  which is §5's design rather than a defect.
- **(21) animation-group membership.** The refusal the owner remembered shipped 2026-09-03 (§2.29); what
  is open is **retagging**, which changes the meaning of every key on both groups' tracks.
- **(22)** and **(10)** deprioritised by the owner; **(37)**'s importer dropped.
- **BUGS.md's five remaining `.popover`s** have the timeline's swallow-every-drag defect. Three are
  colour pickers whose chrome would visibly change — the owner's call, as it was for the timeline's four.
- **The pencil half of (47)** cannot be driven by any test here: XCUITest cannot synthesise a pencil.
