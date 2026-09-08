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

**No branches, no worktrees, no quarantine, stash empty.** Fast tier at `4d3ebba`: **3513 total /
3510 passed / 0 failed / 3 skipped**, Debug and Release both, reconciled exactly against 3513 static
`func test` **declarations** across 151 fast-tier files. A naive `grep -c "func test"` over-reads by
exactly 3 — three `private static func testBrush()` helpers.

**Full suite MEASURED at `e6ce40e`** on an idle machine with a freshly erased device: **3714 tests,
3675 passed, 3 failed, 36 skipped, 33 min.** All three failures passed clean in isolation with a count
of 1 each. The class table is in CLAUDE.md; **no split is warranted and the arithmetic says why** —
four clones hold 27.4 min of ideal work, so `BrushEditorUITests` at 558 s is a third of the per-clone
share, not the floor.

**The owner's iPad is an iPad (9th generation), `iPad12,1`, 3 GB RAM** — MEASURED 2026-09-07. **Every
simulator in this repo is an M4/M5 with 8 GB or more, so every memory figure taken on one is suspect on
the owner's device by at least 2.5x.** That generalises well past the item that found it.

## Start here

TODO's top two are both the owner's, both filed 2026-09-07, and **(54) is in flight** — check for a
`tmp/hold` branch before starting it.

1. **(36) is all but done** — projects can live in a folder the artist chooses, with an arbitrarily
   deep tree, interruption-safe migration and a reinstall test. What is left is one bullet:
   `restoreFromTrash` returns a project to the top of the tree rather than its original folder.
2. **(54)** — whether a held frame costs one composite or one per frame. Filed as a question, not an
   optimisation: the design already claims the good behaviour, so if the composite *runs* and only the
   disk write is deduped then every hold in every document pays full price.
3. **(41), then (42)** — the owner set that order. (41)'s remainder is not an optimisation: an element
   that keeps its id through a rewrite has no rectangle that says which footprint stopped being true,
   and this item's own text records that *"there is no design left to do"* was wrong **twice**. Brief it
   as a design problem with a written proposal before a line is edited.

## What shipped in this pass

**(53)** the 8 fps keyframed-playback stall · **(51)** onion-skin opacity · **(52)** refuted, already
fixed · **(47)** the pen-only finger tap · **(12)** animated Distort · **(26)** import videos · **(31)**
the canvas cap · **(36)** chosen-folder storage · stage 7's editable fps and slider take recorder · and
**(45)**'s prune of the specs.

- **(53)**: `sandwichEngagesOnCanvas` engages on a container pose, so a keyframed move serves the baked
  frame instead of rasterizing posed ink once a tick — **72.8 ms → 3.31 ms a frame**, MEASURED in
  Release on an idle machine. A **cel's own** pose channel has the identical defect at 73.6 ms and is
  deliberately left open in BUGS.md, because engaging there would make a drag show a stale composite.
- **(31)**: `maxCanvasExtent` is **6000**, MEASURED on the owner's iPad — a fresh document survived
  12000 and died at 13000. **At 16383 the footprint is flat through the whole gesture and explodes
  6.6 s after pen-up**, so the dabs are cheap and the commit is what kills it.
- **(36)**: the reason it was fast-tracked is that a measurement pass **wiped the owner's iPad
  container** on 2026-09-07, destroying their `AnimationTest` document with no recovery.
  `-resetGallery` did it, from a Release build on a physical device. It is now refused off the
  simulator **and** forgets the chosen-folder bookmark before wiping, because it resolves its
  directories through `ProjectLocation` and would otherwise reach outside the container entirely.

## What this pass paid for, and it was expensive

**Subagents spawned subagents.** Three briefed agents became **seven running agents**, because
`general-purpose` carries the Agent tool and no brief forbade delegating. With a cap misread as "1 Opus
**plus** 2 Sonnet" when it is **1 Opus *or* 2 Sonnet**, this burned millions of tokens, hit the usage
limit, and killed five agents mid-task — creating a three-branch quarantine that took a full session to
clear. **Every brief must say: do not spawn subagents.** Check `ListAgents` shows zero running before
launching, because **a `completed` notification does not mean an agent is finished** — one resumed an
hour later and two Opus agents ended up in the same worktree.

**Every audit of that quarantine found something the diff did not show**: a test whose pixel probe
fired at frame 0 where the pose *is* rest, so it agreed under any implementation; a bench whose
`tearDown` trapped on the skip path and **red every full suite**; a frame rate that could change under a
running take. None of it was visible without mutation-testing each assertion.

**And the disk filled to 186 MB free**, because every killed agent left a ~3.5 GB simulator device
behind and thirteen accumulated. **Create a device, delete it immediately after the run that needed
it** — not at the end of the task.

## Waiting on the owner

- **(21) stage 7's other half** — §5 asks for one mechanism on two surfaces and only the slider is
  built. The Move box needs rulings on resampling and tolerance for a **quad**, which `ValueRecording`
  cannot express; §5's slow-motion multiplier is unbuilt for the same reason. Stage 10 waits on a whole
  stage 7.
- **(21) animation-group membership** — the refusal the owner remembered shipped 2026-09-03 (§2.29), so
  what is open is **retagging**, which changes the meaning of every key on both groups' tracks.
- **(22)** deprioritised by the owner, **(10)** deprioritised, **(37)**'s importer dropped.
- **BUGS.md's five remaining `.popover`s** have the timeline's swallow-every-drag defect; three are
  colour pickers whose chrome would visibly change, which is the owner's call.
- **The pencil half of (47)** cannot be driven by any test here — XCUITest cannot synthesise a pencil.
