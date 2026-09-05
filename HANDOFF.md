# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — the brush engine, and there is a decision owed before the next stage starts

**[BRUSH.md](BRUSH.md) is the specification. §2 is twenty-three owner rulings — read them rather than
re-deriving them**, §12 is the build order with a DONE marker per stage, §13 is what is still open.

**Stages 0 through 8 are merged, §2.22 is built, and §12 stage 9's *container* is built** — the
brushes menu, its groups, and the door to the editor. TODO (37) describes the whole of it in one
paragraph.

**Start at the editor — §7.2, §12 stage 10.** The door exists and behind it is a shell holding exactly
the six sliders the old panel had. What it owes: the three columns, the categories §7.2 names, the
curve editor (which is `TimelineGraphBand`'s control over a different domain, per §7's four numbered
points — **its y axis must be fixed, not auto-ranged**, which is the defect the owner found on the
device in TODO (38)), and **the drawing pad**, which is the owner's own stated reason for wanting the
feature at all.

**Two things in the model are reachable only from code until that editor exists**, and both are owed a
control by it: **§2.22's second input** — a row's gain, with an explicit *none* — and every parameter
§7 lists as having no UI (`scatter`, the angle's three contributions, `hardness`, `density` and its λ,
`blendMode`, the three HSB shifts, and §8.4's edge softness).

**Then §12 stage 9's contents.** The set is **designed, not assembled** (§8.4): a CC0 pack is starting
stock, tips are drawn and settings tuned on top of it, and each brush is judged by eye against a contact
sheet before it enters §8.6's table. §8.3's per-file licensing check now has Krita's bundles as a third
source. The owner will give opinions once they can try the set — they said so.

**The device build is the other thing worth more than any offline work.** A Release build has not
reached the iPad since `2bef347`, which is many merges stale, and the owner has said the brush decisions
are best made with it in their hands: *"I think these brush decisions are best done when i get it
physically on my ipad, and i can edit aspects of it myself to see which settings are good."* Stage 8
changed how every stroke composites, so a build now is worth taking even before stage 9.

## Ask the owner these

- **Nothing blocks work.** The owner's standing answer covers the next stage: *"Get something working
  that i can interact with on the ipad and ill tell you if i want changes."* Build the editor, put it on
  the device, and ask then.
- **Drive a real Pencil across the canvas and lean it over.** The simulator cannot synthesise pencil
  input at all, so **non-neutral tilt has only ever been exercised by tests, never by hardware.** Stage
  4 stores altitude and azimuth and stage 7 reads them; nothing has confirmed the hardware end. A
  current build is on the device now, so this is ten seconds of the owner's time and it closes a gap no
  test in this project can.
- **Warn them about the Pencil preset before they draw with it.** It ships at 90% opacity with ~25 dabs
  overlapping any point, so it used to saturate solid black and now stops at 90%. That is stage 8
  working, and it will read as a regression on first contact.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**`main` is at `032efa1` plus docs. Nothing is in flight; no worktrees, no `tmp/*` branches, nothing
uncommitted.**

**Fast tier: 3074 total / 3071 passed / 0 failed / 3 skipped.** It was 3044 at the start of the pass.

**The full suite is green at `032efa1` — 3241 tests, 3222 passed, 0 failed, 19 skipped, 28:55 on an idle
erased machine, and it is a rare run with no environmental red at all.** Its class table is re-taken in
CLAUDE.md, together with the finding that **a single class's seconds are noisier than they look**: at 160
classes across four clones, which classes share a clone moves them, and two ten-test classes went
opposite ways by ~45% and ~25% this run with no change to either. **Nothing is owed.**

**A Release build of `032efa1` is on the owner's iPad**, installed and confirmed by the owner. The
first `install` failed with `CoreDeviceError 4000` — a *connection* error the deploy section did not
carry — and `devicectl device info details` re-established the tunnel exactly as it does for the
documented `1011`, after which the install succeeded. The device read `available (paired)` throughout.

## What stage 8 settled, because it is easy to re-open by accident

- **Opacity and Flow are two things now.** A dab lays down its `flow` and nothing else; the stroke
  merges once, through its own buffer, at its own opacity and blend mode. So a stroke reaches its
  opacity however often it crosses itself — MEASURED on the simulator at a flat **0.431** across a
  stroke drawn at 44% that crosses itself five times, where the old engine read **0.676** at every
  crossing. The eraser obeys the same rule, by holding *coverage* and punching once.
- **The `opacity` output is deleted**, not deprecated. `channelBase`'s number 2 is left unused on
  purpose — that field's own instruction is *add cases, never renumber*, and a renumber re-rolls every
  randomised stroke.
- **The merge cannot be given a computed bound**, and the attempt is instructive: `ResponseCurve`
  deliberately does not clamp, so `Σ|amount|` bounds nothing, and a box that is too small does not cost
  memory — it **clips ink**. The group takes the union of the rectangles the dabs actually painted.
- **A fractional clip is not free.** Clipping to that exact union antialiases the group's outermost
  pixel row — MEASURED alpha 193 where 255 was drawn — which four existing zero-tolerance parity tests
  caught as *ink lost at a seam*. `.integral` fixes it, and with it a buffered stroke is
  **byte-identical** to a directly stamped one, which the brief had expected to differ by 1-2 LSB.
- **The buffer costs a MEASURED 852 µs a stroke, 6%**, on 200 strokes of 2,301 dabs into a 2048²
  texture. §13's "unmeasured" entry is retired. The one term that is not bounded — a corner-to-corner
  stroke at 16383² makes a canvas-sized group — is inherent to §2.11 rather than to this implementation.

## Four rulings the owner made this pass that outlive the stage

- **§2.20 — a brush parameter is changed in the brush editor and nowhere else.** The side toolbar keeps
  size and opacity, the artist's own two numbers, and **gains nothing, ever**. The navigation is ruled
  with it: tapping the brush icon while it is already selected opens the brushes menu, one tap selects,
  and a second tap on the selected brush opens the editor. A Flow slider built into the stroke panel
  during stage 8 was reverted under this ruling.
- **§2.21 — an imported brush arrives with its dynamics mapped, not merely its tip**, so §12 stage 12 is
  an **adapter onto §6's matrix** rather than a bitmap reader.
- **§2.22 — a modulation row carries a second input whose reading multiplies the first.** The owner
  handed the choice back and named the criterion: *"clean architecture is critical so it could be
  replaced easily."* A flat second slot **is** a one-row nested matrix, so CSP's nested `amount` can
  subsume it later with nothing un-built — where nesting first would have made the hot per-dab loop
  recursive. **A second input attenuates**; `amount` stays the only signed, unclamped term.
- **§2.23 — not every brush is a dab walk.** The owner's fill brush (draw a contour, it fills at
  pen-up) and its siblings are **unscheduled**, and the ruling is a constraint on everything before
  them: a stored stroke becomes ink at **one site per tier** and `VectorStroke` knows nothing about
  dabs, so such a brush needs no new storage and no format change. What must not happen is "walk the
  path and stamp" leaking into a third place.

**And one spec claim was refuted by the code**: §8.2 said brush groups should reuse the layer tree.
`Layer`/`LayerFolder` are two concrete layer-shaped structs with no node generic over a payload, and a
`LayerFolder` **has no ordering field at all** — position is derived from where its contents sit, so an
empty folder sorts to the top and a new brush group would have jumped the moment it was filled. Groups
are a flat list, and §8.2 says so now.

## Filed rather than fixed, and each is a decision rather than a backlog entry

- **The vanishing stroke has no small fix.** During a re-walk both of `refreshDisplay`'s relevant arms
  return without touching the image view, and there is one scratch view.
- **Undo charges 3-6x what an entry retains**, because copy-on-write shares the sample arrays.
- **Nothing batches per-cel content restores across several cels into one undo step.** This is what
  blocks §2.10's layer and document scopes.
- **`roundness` is declared in §6 and deliberately not built.** It contradicts §3.5's square-mask ruling.
  Nothing needs it before stage 9's chisel and flat tips.

## Everything else open, none of it touched this pass

**TODO (39) is the owner's three timeline defects**, all from the device; its freeze lead is the owner's
own observation and worth more than any tracing — **ask them to leave "Record My Actions" running.**
**(40) is onion skin z-order**, where a built fix was dropped unmerged and both sides are on the record.
Three survey defects are in BUGS.md: Flip on a vector layer does nothing and clears the undo stack anyway;
Merge Down on a transformation layer deletes it unprompted; a pose-channel row can raise no box.
**Video's remaining stage is (26) §8 stage 8.** **(21) keyframes**: 5b, 6, 7, 8, 10 and folder-level
transforms. **(29) rendering**: stage 7, the memory audit. **(41) and (42)** are the middle-of-list edit
and the live selection adjustment that depends on it. (22), (24), (27), (28), (30), (31), (35), (36) are
unstarted and the last group needs a design conversation each.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. **Two agents at a time is the cap** the owner set
   this pass — and **forbid sub-spawning in the brief**, because an agent with the full tool set spawns
   its own helpers and the count you stated is not the count that runs.
2. **When something needs the owner's call, ask it through the question prompt** — not as prose at the
   end of a summary, which they may not read.
3. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be".
4. **A replaced path is deleted, not left beside the new one.**
5. **At most one investigation agent at a time.** Building is separate.
6. **Weighty programs may be killed to free the machine.** Standing permission.
7. **Show, do not describe.** Anything whose answer is visual goes to the owner as a picture.
8. **Explain a new feature as if they know the program and nothing of the feature.** No jargon, and name
   the artist-facing consequence rather than the mechanism.

## Traps this pass paid for

- **`SendMessage` is documented and not available.** `ListAgents` prints a subagent's address and tells
  you to message it; the tool is in neither the available nor the deferred set. **So a brief cannot be
  corrected once the agent is running** — get it right, or accept reverting afterwards. The owner
  believes previous sessions had it; do not spend context on it.
- **An agent with the full tool set spawns its own subagents**, so "two agents" became four. Say *"do
  not spawn subagents of your own"* in every brief.
- **`git merge --ff-only tmp/x` run from inside the tmp worktree merges nothing** and says "Already up
  to date". Always `git -C <main worktree>`. This file's memory records it four times; it happened a
  fifth.
- **`CoreDeviceError 4000` is a connection error the deploy section did not carry**, and it takes the
  same cure as the documented `1011`: `devicectl device info details` re-establishes the tunnel and the
  next install succeeds. Retrying `install` alone does not.
- **Four of five prescriptions in each build brief were refuted again**, which is six passes running.
  This pass: the merge could not be given a computed bound (`ResponseCurve` does not clamp, so `Σ|amount|`
  bounds nothing and a short box *clips ink*); a fractional clip antialiases a group's outer pixel row;
  §2.22's channel needed a whole plane rather than an offset, because an offset inside an output's block
  halves the stride and reintroduces the collision that field's own doc reasons about; `readsTaper` had
  the same blind spot as `isPressureOnly` and the brief named only one; and §8.2's layer-tree reuse was
  wrong three ways over.
- **A test in a brief can be one that passes against the feature not being built.** §2.22's brief asked
  for `random × pressure` against `random` + `pressure` — but those differ *anyway* when the gain is
  ignored. It needed a third render to be the operand that catches it. The two-operands rule applies to
  the orchestrator's briefs, not only to the worker's code.
- **A per-class second is noisier than it looks** at 160 classes over four clones: two unchanged
  ten-test classes moved ~45% and ~25% in opposite directions between consecutive full runs. Trend the
  total; treat one class's rise as signal only when it repeats.
