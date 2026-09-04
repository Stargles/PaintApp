# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — this session is the brush engine, and the owner is holding your context for it

**The owner's instruction, closing the previous pass:** *"the next session's context will likely be fully
reserved for brush engine so I can pin down the feature."* So **do not pick up video, keyframes or the
defect backlog** unless they ask. They are recorded below and they can wait.

**[BRUSH.md](BRUSH.md) is the specification and it is finished.** §1 is the ask verbatim, **§2 is sixteen
owner rulings — read them rather than re-deriving them**, §9 is the deletion ledger, §11 is the build
order. [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) is the survey that preceded it and
is still accurate about the seams.

**§12 stage 0 is done** — the path refit landed and `StrokeSampleGate` is deleted. `StrokePathFit`
decides what is stored (a fixed 0.25 pt deviation tolerance and a 12 pt cap, no brush anywhere) and
`StrokePath` is the curve every tier walks. **§3.3 was rewritten by building it**: it had specified
cubic control points as the stored record, and the point list survived instead — read §3.3's three
reasons before reopening that. **Start at §12 stage 1**, randomness by hash, which deletes
`DiscardedDabTarget`.

**Four rulings shape everything and are the ones a session will otherwise re-derive.** Per-dab randomness
is `hash(strokeSeed, arcLength)` and never a sequential stream — §4, and it is what survives a split, a
refit, a spacing edit and an eraser punch alike. Grain is deleted entirely, canvas-anchored paper texture
included. Brushes deduplicate into a document-level table, frozen per stroke, with an explicit
apply-to-existing verb. And **§5.5's tilt seam is a build requirement of stage 4, not of the stage that
eventually adds tilt** — including that `StrokeInput`'s tilt capture is a named exception to the standing
delete-what-is-unused rule.

**The owner will send reference artwork** to pin down which brushes ship. They know the matching loop
cannot close until the tip generator exists (§11 stage 9); images sent earlier sharpen §8.6's set list.

**§8.3 is a licensing constraint, not a taste one.** Artist brush packs — Procreate, `.abr`, Gumroad —
are licensed to make artwork with and not to redistribute inside software, so almost nothing on the
internet may ship. **Every CC0 claim in §8.3 must be re-checked against its source before an asset is
committed**; nobody has done that.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**Nothing is in flight. No worktrees, no `tmp/*` branches, nothing uncommitted.** `main` is `2bef347`.

**Fast tier: 2919 total / 2916 passed / 0 failed / 3 skipped.** It was 2698 at the start of the pass.

**The full suite is green and was run this pass: 3048 total / 3042 passed / 0 failed / 6 skipped**, with
**no environmental red at all**, which CLAUDE.md's history says is unusual. Its class table is re-taken
there; its wall clock is deliberately not recorded, because two logic runs were queued alongside it.

**A Release build of `2bef347` is on the owner's iPad.**

## Read CLAUDE.md's newest section before you brief anybody

**"A feature is not finished because its model is correct — drive it before you call it done."** It was
written this pass because **three features reached the owner's iPad unusable**, each with a green fast
tier, mutation-tested assertions and a worker report describing it as complete. The owner found all three
in about a minute.

The cause is structural and it still applies to every brief you write: **every test in this repo reaches
the model and asserts a stored value**, so the suite is blind by construction to a correct value drawn in
the wrong place, and to a feature whose only entry point requires state that only that entry point can
create. **The bar is the orchestrator's to set and it was set wrong** — those briefs asked for round
trips, cache keys, mutation tests and refutations and got all of them. None asked whether a person could
use the result.

The proof that the fix works: the agent sent to make the transformation layer reachable **drove the
simulator and found a third defect no test in this project could ever have caught** — the feature's only
menu entry sat below a thirteen-item catalogue, past the point an accessibility client can see a menu
item at all. Reachable by a human scrolling; invisible to every possible test.

## What landed this pass

**Sixteen merges.** [VIDEO.md](VIDEO.md) and [BRUSH.md](BRUSH.md) were both designed from the owner's
briefing and written; video went from a word in a TODO to import, crop, Adjust Speed, split and playback;
the transformation layer was built model-first and then made reachable; the graph editor gained a
decomposed transform band with draggable nodes and shapeable handles; and the owner's three Move reports
and three small defects are all closed.

**Five owner rulings landed and are recorded where they act**, not here: a lasso catches a video the way
it catches an image and a video never splits ([VIDEO.md](VIDEO.md) §2.10); an animation group moves whole
and on its own (KEYFRAMES §2.29-2.30); merging a blend layer down bakes that one layer's colours and lets
the gaps change ([EFFECT_BACKDROP.md](EFFECT_BACKDROP.md) §2.3); the transform band shows six decomposed
curves; and onion skin should draw in front of everything, which is **reverted and open** below.

## What needs the owner before it is built

- **The value-layer render gate is a live defect in existing documents.** `leafSnapshots` gates every
  leaf on `activeCelIndex`, and `addValueLayer` stamps one cel sized to `sceneFrameCount` **at creation**
  and never extends it. So: add a flat-colour background to a new document, draw out to frame 30, and
  **from frame 12 the background is gone** and an adjustment layer stops grading. BUGS.md carries the
  numbered repro. The fix is a rendering change touching every adjustment layer in every existing
  document, which is why it was filed rather than taken.
- **Onion skin z-order, reverted deliberately.** The fix was built, proved with a pixel assertion and a
  before/after screenshot, and **dropped unmerged at the owner's instruction** because honouring *"in
  front of everything"* literally made the Behind / In Front picker draw the same picture in every
  document, and deleting the picker was too big a consequence to take in passing. **The owner's
  clarification is that Behind should mean behind the *current layer*, not behind everything.** The
  worker refused exactly that design for a stated reason — at rest with the compositor engaged there is
  no active-layer ink to sit under, so `.behind` would mean one thing per rendering path, which is the
  shape of the bug rather than a fix for it. **Both sides are on the record; the next session resolves
  it.** Two findings worth keeping: it is **not a video regression**, a photo has always done this; and
  **TODO item (30) already stated the mechanism verbatim**, filed as a hypothetical cost of a different
  feature and never recognised as live.
- **Animation-group membership editing is unruled, not merely unbuilt.** Retagging an element between
  groups changes the meaning of every key on both tracks — the same question KEYFRAMES §2.29 settles from
  the other side for splitting a group. It needs a conversation.

## Everything else open

**TODO (39) is the owner's three timeline defects**, all from the device: the pinch anchor drifts further
out, the area under the layer rows is dead, and the freeze is back and still not reproducible. **Its
freeze lead is the owner's own observation and is worth more than any tracing** — play runs and the
playhead moves while cels take no tap and the timeline will not drag, so the gesture recognisers are what
is dead. **Ask the owner to leave "Record My Actions" running during an ordinary session**; a device-only
timing bug is exactly what [ActionRecorder](PaintSoftware/Debug/ActionRecorder.swift) exists for.

**Three defects found by survey and filed in BUGS.md, not fixed.** Flip Horizontal/Vertical do nothing on
a vector layer **and clear the undo stack anyway** — and a new document's first layer is vector, so that
is the default case. Merge Down skips the confirmation the pinch path runs, so **Merge Down on a
transformation layer deletes it and bakes nothing, unprompted**. And a pose-channel row in the graph
editor can close the list and raise no box.

**Video's remaining stage is (26) §8 stage 8**, baking to cels of images. Two things are unmeasured and
recorded in its §9: the cost of a backward-seek pipe rebuild on the iPad, and that a backward seek holds
a lock other render workers queue behind. **A rotated clip cannot be tested on this machine at all** — no
generated fixture can carry the rotation tag, so only a phone-shot clip on the device exercises it.

**(21) keyframes**: what remains is 5b (animated Distort), 6, 7, 8 and 10, plus folder-level transforms
having no artist entry of their own. **(29) rendering**: stage 7, the memory audit. (22), (24), (31),
(35), (36), (27), (28), (30) are unstarted, and the last group needs a design conversation each.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. The cap is **3 opus or 6 sonnet at once**.
2. **When something needs the owner's call, ask it through the question prompt** — not as prose at the
   end of a summary. They said so twice in one session.
3. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be".
4. **A replaced path is deleted, not left beside the new one.**
5. **At most one investigation agent at a time.** Building is separate.
6. **Weighty programs may be killed to free the machine.** Standing permission.

## Traps this pass paid for

- **Every brief's prescription is a hypothesis, and this pass refuted more of them than any before it.**
  The transformation layer's spec was wrong in six places. VIDEO.md was wrong in nine, including an
  inverted frame-rate formula and one premise a worker refuted against *itself* when its own test's
  precondition failed. Two of my own prescribed fixes were refuted with proofs — freezing a graph axis
  during a drag cannot work, because any axis fitted to the keys is affine-equivariant and sends a
  two-point set to the same two positions whatever the points are.
- **Six existing tests were found either pinning a defect as a feature or measuring nothing** — one
  captioned in as many words with the hard-coded behaviour it locked in, two whose operands could never
  move, one asserting a layer was raster when it started raster. All green. The suite growing from 2698
  to 2919 matters less than that.
- **`git merge --ff-only` run from inside the branch's own worktree merges the branch into itself**,
  prints "Already up to date", and the push says "Everything up-to-date". Both read as success. Merge
  with `git -C <main worktree>` — it has now cost five sessions.
- **A rebase that resolves cleanly is not a semantic merge.** Every one of the sixteen merges was
  re-verified on the merged tree, and the count reconciled against the arithmetic rather than read off
  the banner. Two hand-resolved conflicts in live code needed exactly that.
