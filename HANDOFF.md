# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — two branches are finished-but-unverified and must land before anything else

**Neither is merged and neither has had a fast tier run at its final commit.** Both were stopped
mid-flight when the owner hit a usage limit, not because anything was wrong.

- **`tmp/area` (`8cc8ff8`, worktree `../PaintApp-area`) — TODO (41), the owner's lag spike.** Three
  commits: a cel repairs the rectangle an edit touched instead of re-walking itself, a repair that
  escapes its rectangle widens rather than giving up, and eleven tests. **It was interrupted part-way
  through mutation-testing.** One live mutation — a deleted `cg.clear(clip)` in `VectorLayer.swift` —
  was reverted by hand at close-out, so the tree is clean, but **the mutation run was not finished**:
  re-run it before trusting the tests.
- **`tmp/fold` (`406fe84`, worktree `../PaintApp-fold`) — the owner's tuned Rough Ink becomes the
  shipped one, and a library that cannot be decoded is preserved rather than silently replaced.** Tree
  clean, all eight mutations reported caught, and it was about to run the fast tier when it stopped.
  `../PaintApp-fold-base` is a throwaway baseline worktree it made; delete it.

Rebase each onto `main`, run the fast tier **verbatim** per CLAUDE.md, read the count from
`xcresulttool`, and merge. Expect conflicts: three landed today from two agents touching one enum or
one digest table, and every one was caught at the merge as a compile error.

**Then a full suite.** The last full run was at `032efa1` — **2482 tests, 21.7 min**, and thirty-odd
merges have landed since, including the render path (§12 stage 8's per-stroke buffer) and the walk
(§2.28's module chains). It is owed and it is the biggest unknown in the tree.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**`main` is `25915ed`. 74 commits today. Fast tier 3159 total / 3156 passed / 0 failed / 3 skipped.**

**A Release build of the brush pack is on the owner's iPad, signed until 2026-09-12.** It does **not**
carry the last four merges (density-as-a-gate, the editor's draft/Cancel, gain, two-axis scatter), and
it does not carry either branch above.

## The brush engine is built — §12 stages 0 through 11 are DONE

[BRUSH.md](BRUSH.md) is the specification. **§2 is thirty-three owner rulings; read them rather than
re-deriving them.** Eleven of them were made today and four supersede earlier ones — §2.28 supersedes
§2.22's fixed shape, §2.29 supersedes §2.22's uncurved clause, §2.31 carves an exception out of §2.10,
and §2.32 supersedes §2.18's intrinsic draw.

**What shipped today**: opacity and flow split with a real per-stroke buffer; canvas-anchored texture;
the brushes menu with groups and the owner's two-tap navigation; the full-screen editor with orderable
module chains, noise octaves, second inputs carrying their own curves, and typed values past 100%;
relocatable storage; **twenty brushes in five groups, every asset generated, no third-party content at
all**; and `density` as a threshold so its randomness lives on the chain.

**What is left of (37)**: **§12 stage 12 only** — the `.abr` / Procreate `.brushset` / Clip Studio
`.sut` importers. The owner named those three and left the timing to me; it stays last because the
model moved five times today and an adapter aimed at a moving target is written twice. **§12 stage 12
carries what is known about each container, to be verified rather than trusted.** Test files are a real
dependency: source freely-licensed samples first, and only ask the owner for their Procreate packs if
those prove too thin.

## Ask the owner these

- **Their tuning pass.** They have the brush pack and said Rough Ink *"looks almost exactly like how I
  want it now"*. `tmp/fold` folds that in. Once it lands, ship a build and ask them to go through the
  other nineteen — the loop they specified is tune, extract, done.
- **Drive a real Pencil and lean it over.** The simulator cannot synthesise pencil input, so **tilt has
  never been exercised by hardware** — two stages store and read it and nothing has confirmed the
  hardware end. Ten seconds of their time closes a gap no test here can.
- **Splatter and Stipple want revisiting now that §2.30 exists.** §12 stage 11 shipped them as pictures
  because nothing could offset a dab *across* the path; two-axis scatter merged the same hour and is
  exactly that lever.

## Filed rather than fixed

- **[BUGS.md](BUGS.md) — the auto-resign daemon counts its own runs, not the profile's expiry.** It
  reported "3d remaining" on a profile that expired ten hours later, which is why the owner's app has
  died several times. The fix is to read `ExpirationDate` out of the profile. **Recovery is in the entry
  and the obvious move fails**: rebuilding re-embeds the cached expired profile, so delete
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision` first.
- **BUGS.md — a restored project texture can be held down by a negative cache entry.** Pre-existing;
  wants fixing with §13's document-opened-on-a-second-device case, which is the only way to reach it.
- **§13 — the owner's fixture cannot be decoded by `main`**, because it predates §2.30. `tmp/fold`
  addresses it; if that branch is abandoned, this is a data-loss path.

## What today cost, MEASURED

- A module is **~0.06 µs**; an empty chain is free. A whole re-walk is **+3.3–4.3%** for chains.
- **An octave is 0.24–0.26 µs** — four times a module, and the steepest purchase on the path. Capped at 8.
- §12 stage 8's stroke group is **~852 µs a stroke, ~6%** of a full re-walk.
- The editor's pad re-walk is **18–42 ms** per change (Debug, simulator) and does **not** fit a frame,
  so the pad caps at 8 strokes. Release could not be measured: `xcodebuild test -configuration Release`
  fails on this project with a pre-existing `@testable import` module error. **That is worth fixing** —
  it means no timing has ever been taken in the configuration that ships.

## Traps this pass paid for

- **A green check is evidence about the tree that existed when you ran it.** A rebase output filtered to
  two lines hid a conflict; a suite was then run on a half-rebased tree and its number reported. It was
  fine, and "happened to be fine" is not verification.
- **The simulator you are *driving* is a binary too.** CLAUDE.md now carries it: `simctl install` ships
  whatever the last `xcodebuild` wrote, including the build that mutation-tested an assertion. One
  session diagnosed a shipped defect that existed only in the installed bundle.
- **An assertion can be true of the world when written rather than true of the thing it names.** A test
  called "the collections are disjoint" asserted the tip list is exactly `[.square]`, and eleven shipped
  tips reddened it. It asserts the partition now and cannot be broken by adding a brush.
- **A test written to catch a class of defect can itself be broken and say so about itself.** The
  identifier census added this afternoon had been red on `main` since the brush pack shipped.
- **Cross-branch collisions are caught at the merge, not before.** Three today, each a compile error at
  rebase: two enums grown independently, a preset deleted by one branch and named by another's new test,
  a channel renamed by one branch and used by another.
