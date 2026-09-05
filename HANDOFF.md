# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — the brush engine, and there is a decision owed before the next stage starts

**[BRUSH.md](BRUSH.md) is the specification. §2 is twenty-two owner rulings — read them rather than
re-deriving them**, §12 is the build order with a DONE marker per stage, §13 is what is still open.

**Stages 0 through 8 are merged.** TODO (37) describes what that means in one paragraph.

**§13's sum-versus-product question is answered — §2.22, and it is unbuilt.** A modulation row gains a
**second input whose reading multiplies the first**, so `output = base + Σ amount · curve(input) ·
reading(second)`. The owner handed the choice back — *"i really don't know, your call ... clean
architecture is critical so it could be replaced easily"* — and that last clause is what chose it over
CSP's nested `amount`: a flat second slot is one multiply in `Brush.dabValues`, which is the hot per-dab
loop, and it **is** a one-row nested matrix, so nesting can subsume it later with nothing un-built.
Build it before the editor; §2.22 carries the two traps (a row with `random` in *both* slots needs a
second channel, and the second input is not curved).

**The owner's steer for what comes next is explicit**: *"Get something working that i can interact with
on the ipad and ill tell you if i want changes."* So the editor and the library — §2.20's brushes menu,
reached by a second tap on the already-selected brush icon — are worth more than any amount of offline
brush tuning, and §12's ordering of the library before the editor should be re-read against that rather
than followed out of habit.

**Then stage 9, and it is driven by contact sheet.** Render candidates through the real stamper, put
them in front of the owner, build only what they pick. That is the loop that settled §8.4 and it is the
instruction for the whole ~24-30 brush set.

**The device build is the other thing worth more than any offline work.** A Release build has not
reached the iPad since `2bef347`, which is many merges stale, and the owner has said the brush decisions
are best made with it in their hands: *"I think these brush decisions are best done when i get it
physically on my ipad, and i can edit aspects of it myself to see which settings are good."* Stage 8
changed how every stroke composites, so a build now is worth taking even before stage 9.

## Ask the owner these

- **§13's sum-versus-product question, above.** It gates the editor and it is the only thing on this
  list that blocks work.
- **Drive a real Pencil across the canvas and lean it over.** The simulator cannot synthesise pencil
  input at all, so **non-neutral tilt has only ever been exercised by tests, never by hardware.** Stage
  4 stores altitude and azimuth and stage 7 reads them; nothing has confirmed the hardware end. This
  needs a fresh build on the device first.
- **The Import Custom Brush row sits below the fold** in the brush panel and needs a scroll. It works —
  it is just not where they would find it. §2.20's brushes menu is where it is going anyway, so this may
  answer itself.
- **Warn them about the Pencil preset before they draw with it.** It ships at 90% opacity with ~25 dabs
  overlapping any point, so it used to saturate solid black and now stops at 90%. That is stage 8
  working, and it will read as a regression on first contact.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**`main` is at stage 8's merge. Nothing is in flight; no worktrees, no `tmp/*` branches, nothing
uncommitted.**

**Fast tier: 3050 total / 3047 passed / 0 failed / 3 skipped.** It was 3044 at the start of the pass;
the six new tests are stage 8's.

**The full suite is green at `7605169`, run after stage 8 merged** — 3212 tests, 3192 passed, 1 failed,
19 skipped, 25:02 on an idle erased machine. The one failure is `InterpolationWorkflowUITests`'
`testInterpolateModeEndToEndFromGestureToScrub`, **which passed clean in isolation** and is the same test
that failed environmentally at `77430e1`; CLAUDE.md now says to treat a red there as environmental until
an isolated run says otherwise. Its class table is re-taken in CLAUDE.md — **nothing is owed.**

**A Release build of `2bef347` is on the owner's iPad and is many merges stale.**

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

## Two rulings the owner made this pass that outlive the stage

- **§2.20 — a brush parameter is changed in the brush editor and nowhere else.** The side toolbar keeps
  size and opacity, the artist's own two numbers, and **gains nothing, ever**. The navigation is ruled
  with it: tapping the brush icon while it is already selected opens the brushes menu — the library in
  its folders, with an **Add brush** button that is where the importers land — one tap selects a brush,
  and a second tap on the selected brush opens the editor. `StrokeSettingsPanel`'s pressure, spacing and
  stabilization sliders are what that editor **absorbs**; they are not a second home. A Flow slider
  built into that panel during stage 8 was reverted under this ruling.
- **§2.21 — an imported brush arrives with its dynamics mapped, not merely its tip.** So §12 stage 12 is
  an **adapter onto §6's matrix** rather than a bitmap reader: what the file says about pressure, tilt,
  spacing, jitter and scatter becomes rows, and what it does not say is left at the neutral rather than
  invented.

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
  you to message it; the tool is in neither the available nor the deferred set, and two searches found
  nothing. **So a brief cannot be corrected once the agent is running** — get the brief right, or accept
  reverting afterwards. The owner believes previous sessions had it, so this may be a bug rather than a
  design; do not spend context on it.
- **An agent with the full tool set spawns its own subagents**, so "two agents" became four. Say *"do
  not spawn subagents of your own"* in every brief.
- **A worker's report is evidence, not fact.** Verify against the tree and the xcresult before merging.
  This one held up on every count checked, including the test count re-run after a local edit — but the
  local edit is the point: the count the worker reports is for the tree the worker had.
- **Four of five prescriptions in this pass's build brief were refuted**, which is now five passes
  running. Invite refutation explicitly; it is where the value is.
