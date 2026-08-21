# Prompt for the next session

Paste the block below.

---

Read HANDOFF.md, then CLAUDE.md and TODO.md.

**The performance programme is confirmed on hardware.** The owner ran a Release build of `38e22c6` on
their iPad 9 and all seven device checks came back clean — *"17fps is gone, good job. 4k screen
displays full 60fps when painting,"* *"leaving the gallery is instant,"* *"no issues"* opening a
project, *"lasso fill works,"* *"cross eraser works as intended, very nice,"* *"text handles are
good,"* and Add Text with the keyboard up read as "not much of a problem." All four of the owner's
originally reported bugs are confirmed fixed on hardware. `main` is at 1478 fast-tier tests passing, 0
failing, 3 skipped (1481 total). No worktrees, no `tmp/*` branches, no simulator debris.

**One item moved anyway**: `PERFORMANCE.md` item 14 (raster-cel residency) was re-opened by the
owner's stated intent for a real document (300–1000 drawn cels), then re-scoped by reading their
actual iPad container — the largest of 25 real packages has 4 cels, so that intent describes forward
work rather than a fire. The expensive fix stays declined; a cheap, correctness-clean half (stop
writing/loading a raster tier for cels with no raster content) is newly justified and queued.

**Four new owner asks arrived after the device pass, about the lasso and move tools on a vector
layer** — full text in `TODO.md`'s Queued section:
1. A lassoed move should move only the selected part (splitting stroke geometry, cutting fill regions)
   — text excepted, which the owner has already ruled is fine to move whole.
2. The lasso toolbar icon should stay highlighted while another tool is briefly in use.
3. Move is extremely slow on a vector layer — down to ~5 fps.
4. The move tool's handles don't hold a constant screen size across zoom and don't respond to touch —
   the exact bug `ADD_TEXT.md` §1 predicted, and Add Text Stage 4 shipped the fix's pattern today
   (`TextTransformOverlayView`). Port `ObjectTransformOverlayView` onto it rather than redesigning.

Eight rulings the owner still owes are listed at the end of `HANDOFF.md`; none of them gate anything.

**Delegate.** The owner's standing instruction is that this session is an orchestrator: *"save your
context by smartly delegating tasks to sonnet and opus agents"*, and *"if there was a restriction of
using agents anywhere, remove it. You should just be smart in usage."* There is no cap on streams.
The real throttle is `tools/simlock.sh`'s two slots, which serialize test runs on their own, so extra
agents queue rather than starve the machine. Give each agent its **own** simulator to create and
delete, tell it never to run `simctl shutdown all`, and tell it to **block on its own test runs** —
an agent stalled overnight by ending its turn to wait for one, and had to be restarted.

Then, in rough order of value:

1. **The four new owner asks above**, especially (4) — it has a working reference implementation in
   the tree already (`Views/TextTransformOverlayView.swift`, `442dc16`) and is a port, not a design.
2. **`PERFORMANCE.md` item 14's cheap half** — stop writing/loading a raster tier for blank-raster
   cels. Correctness-clean, ready to scope, does not need item 9(c)'s thumbnail precondition.
3. **Add Text Stage 5** — the projective distort. `ADD_TEXT.md` §4 rule 9 requires a Release build on
   the iPad 9 before merge, same as every stage touching the warp path.
4. **The Mode 3 eraser's ~95 ms per cutting sample** — measured, deliberately unfixed. Compounds with
   the new footprint eraser, which cuts every stroke it covers rather than one.

---

## Notes for whoever writes the next prompt

**Reading the device directly can settle in thirty seconds what a code-tracing pass cannot settle at
all.** `devicectl` pulling the owner's actual package and manifest is what refuted a standing ~150-cel
inference this pass — the third or fourth time now that the owner's own hardware has beaten an agent
reading code. Reach for it before a multi-agent scoping pass, not only after one.

**A number can be right and its unit label wrong at the same time.** `PERFORMANCE.md` item 14's
"787 MB" and "6.6 MiB" were only mutually consistent at 6.558 MiB, and both were MiB, not MB — caught
by dividing the reported total back apart, not by rereading the code that produced it.

**A budget that is a sum of ceilings is not a sum of occupancies.** Before costing a new consumer
against a budget total, check how many of that budget's own terms are actually reachable at the
canvas size in question — item 13's 656 MiB looked fully spoken for and a third of it was.

**Check `git log` for a file before building what a document says is outstanding — including within
the same day.** Both `HANDOFF.md` and this file carried "a vector layer's transform is not undoable"
as open after it shipped a few hours earlier in the same session's own history.

**Do not tell an agent to cache a UDID in the scratchpad.** Subagents share the parent session's
scratchpad directory, so a fixed filename is silently overwritten — one agent ran a full suite on
another's simulator, and only the xcresult's `deviceName` caught it.

**Do branch work in a worktree, not by switching branches in the main one.** `.git/hooks/post-checkout`
regenerates the *tracked* `graphify-out/GRAPH_REPORT.md` on every switch, which dirties the tree and
can block a concurrent agent's `--ff-only` merge.
