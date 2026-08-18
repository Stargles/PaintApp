# Prompt for the next session

Paste the block below. Everything after it is context for whoever is writing the next prompt, not for
the agent.

---

Read HANDOFF.md, then CLAUDE.md and TODO.md. Continue the UX pass.

You are the orchestrator: delegate to agents, don't do worker-level tracing yourself. Workflows and
subagents are pre-authorized here.

Start with the lasso fill. It is a live bug I reported on device — circling something fills the whole
canvas — and it is the only thing in flight. It is fully diagnosed and fully specified and **not
built**:

1. `tmp/lasso` (worktree `../PaintApp-lasso`) has two test-only commits: a characterization pinning
   today's wrong behaviour, and a test-side proof that the replacement works with no production change.
   It is based on an older `main` and needs a rebase.
2. LASSO_FILL.md is the specification — the algorithm, its name in the literature, every edge case
   decided, the pixel-level sequence, and where it deliberately diverges from other apps. Do not
   re-derive it and do not re-open the design; it came out of research I asked for and I have ruled on
   the semantics.
3. Three things in it that a careless implementation will get wrong, all recorded there: "the loop is a
   wall" must **not** be implemented literally (the flood has to enter the ring in order to exclude it —
   the wall property comes from the final intersect); `fillExpand` defaults to 2 and must be 0 in this
   mode or the fill runs past the artwork; and **no connected-component filter** — a face's eyes are
   meant to fill with the face.
4. When it's built, deploy it to my iPad and I'll try it. The thing I'll check first is a shape with a
   gap in its outline, and a loop drawn well outside the shape.

Then, in order: Add Text stage 1b (the rest of stage 1 — ADD_TEXT.md, and note Stage 2 is already on
main and must not be rebuilt), and the perf programme's Tier A in PERFORMANCE.md.

Two things I still owe you an answer on — ask me when they block work:
  - Save semantics when a project loaded with something unreadable: may saving overwrite the good
    original, refuse, or prompt?
  - Which faces belong in the font picker's favourites strip.

Two things you owe me a ruling on, from work that merged today. Ask when you get to them, not now:
  - A double-traced ellipse (going round twice) detects as a rectangle. Pre-existing, not a regression.
  - The smart oval has no arc-end handles, so "I drew 100° and wanted 180°" means drawing it again.

---

## Notes for whoever writes the next prompt

**Why the lasso is first and phrased that way.** The owner ruled on the semantics across two answers and
then asked for research rather than accepting a design argument — the research agreed with them and
named the algorithm. Re-opening that design would waste the ruling. The three "careless implementation"
traps are all things a session working from the owner's words alone would get wrong, which is why they
are in the prompt rather than only in the doc.

**What not to put in the prompt.** Don't ask the owner to re-check the lasso on the current build; it is
known broken and they already reported it. Don't ask for the canvas-size recalibration again — it is
settled and at the top of TODO.md.

**Machine state.** No stray simulator clones, one worktree (`../PaintApp-lasso`), one branch
(`tmp/lasso`). The owner's iPad has `main` installed as of this session's end.

**A process trap that cost this session three silent no-ops**: `git merge --ff-only` run from inside a
branch's own worktree prints "Already up to date" and merges nothing. Run merges from the main worktree
as their own command. Also: the agent scratchpad is shared between sessions despite being documented as
isolated — prefix per-agent filenames.
