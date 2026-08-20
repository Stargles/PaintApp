# Prompt for the next session

Paste the block below.

---

Read HANDOFF.md, then CLAUDE.md and TODO.md.

**Nothing is in flight, and the performance programme is finished.** Thirteen branches landed
2026-08-19/20; `TODO.md`'s "In flight" is empty; `main` is at 1426 fast-tier tests, 1423 passing, 0
failing, verified on a fresh simulator *after* the merges rather than only on each branch's own base.
No worktrees, no `tmp/*` branches, no simulator debris.

**The binding constraint is now the owner, not the code.** The iPad read `unavailable` all night, so
none of this has been seen on hardware — every after-figure in `PERFORMANCE.md` is a Debug simulator,
where the shape of a result transfers and the multiplier does not. **Deploy first, then ask.**
HANDOFF.md lists seven on-device checks in priority order; run the deploy steps from `CLAUDE.md` out
of the repo, because `deploy/deploy.sh` pulls `main` and cannot ship branch work.

**Two questions gate real work and are worth asking before anything else:**
1. **How many drawn cels does a real document carry?** A drawn raster cel costs 6.6 MiB resident,
   measured. At 120 cels that is 787 MB unbounded — more than all five budgets combined — and
   `PERFORMANCE.md` item 14 becomes urgent. At 30 it is ~200 MB and the item does not exist.
2. **Is 192 MiB of undo (about 12 whole-cel operations) enough**, and is trimming to half on a memory
   warning generous or stingy? `UndoHistory.currentCost` now exists so a session can be sampled
   rather than argued about.

Eight more rulings are listed at the end of HANDOFF.md; several are one-line answers.

**Delegate.** The owner's standing instruction is that this session is an orchestrator: *"save your
context by smartly delegating tasks to sonnet and opus agents"*, and *"if there was a restriction of
using agents anywhere, remove it. You should just be smart in usage."* There is no cap on streams.
The real throttle is `tools/simlock.sh`'s two slots, which serialize test runs on their own, so extra
agents queue rather than starve the machine. Give each agent its **own** simulator to create and
delete, tell it never to run `simctl shutdown all`, and tell it to **block on its own test runs** —
an agent stalled overnight by ending its turn to wait for one, and had to be restarted.

Then, in rough order of value:

1. **Add Text stages 4 and 5** — rotate/scale with handles, then the projective distort. `ADD_TEXT.md`
   §3 has the file-by-file scope; §4 rule 9 requires a Release build on the iPad 9 before Stage 5
   merges. Stages 1 and 3 are done; **stage 2 is on `main` and must not be rebuilt.**
2. **A vector layer's transform is not undoable** — new in `BUGS.md`, wants its own branch. The
   obvious fix is wrong: `objectTransformChanged` fires continuously during the drag, so per-call
   undo would push hundreds of steps for one gesture. It wants a bracket, and the two paths where
   `isVectorTransforming` turns off without a gesture ending are where a bracket would leak.
3. **Item 14, only if the cel-count answer says so** — and thumbnails must be persisted first, which
   item 9(c) made a precondition.
4. **The Mode 3 eraser's ~95 ms per cutting sample.** Measured, deliberately unfixed. It compounds
   with the new footprint eraser, which cuts every stroke it covers rather than one.

---

## Notes for whoever writes the next prompt

**Check `git log` for a file before building what a document says is outstanding.** `PERFORMANCE.md`
and `BUGS.md` both described the `scenePhase` triple-save as to-do for two days after it was fixed;
an agent went to build it and found it already there.

**Tell agents how to measure, not just what to measure.** The three best results of this pass all came
from the same discipline: measure both arms *alternately in one run* so the ratio is contention-proof,
and name an unchanged phase as a control. Contention on this Mac does not widen the error bar — it
changes the answer, 303 vs 527 ms for identical work.

**A decline on a measurement is a good outcome, and saying so up front gets better work.** Item 4b and
item 14 were both declined on numbers, and item 14's decline turned up the more interesting fact —
that the low-risk half of it is worth exactly zero bytes, because `CGContext.makeImage()` shares its
buffer copy-on-write.

**Do not tell an agent to cache a UDID in the scratchpad.** Subagents share the parent session's
scratchpad directory, so a fixed filename is silently overwritten — one agent ran a full suite on
another's simulator, and only the xcresult's `deviceName` caught it.

**Do branch work in a worktree, not by switching branches in the main one.** `.git/hooks/post-checkout`
regenerates the *tracked* `graphify-out/GRAPH_REPORT.md` on every switch, which dirties the tree and
blocked a concurrent agent's `--ff-only` merge this pass.
