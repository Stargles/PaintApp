# Prompt for the next session

Paste the block below.

---

Read HANDOFF.md, then CLAUDE.md and TODO.md. Four branches were stopped mid-flight at a usage limit and
every one of them is committed and pushed — nothing needs recovering, but three carry a `WIP` commit that
is **unreviewed and untested**, so read the diff before trusting any of it.

**Two work streams at a time, maximum.** The owner set that cap explicitly after a four-workflow pass
burned 40% of a five-hour window in fifteen minutes. TODO.md's "three in flight" line is about the Mac's
cores and is superseded. Prefer one scoped agent, or doing it inline; say what a fan-out will cost before
you start it.

Take them in this order, two at a time:

1. **`tmp/fillborder`** — the only clean branch, one commit, test status unknown. Verify the commit
   actually addresses the cause before running anything: the suspicion is *two* stacked bugs, an inset
   artwork rectangle nothing knew about plus an edge rule that was only conditional. Finish and merge.
2. **`tmp/lasso`** — the specified algorithm is in, the WIP on top looks like the failure-signal UI being
   wired. LASSO_FILL.md is the spec, the owner has ruled, do not re-open the design. When it lands,
   deploy to the owner's iPad — they will check a shape with a gap in its outline and a loop drawn well
   outside the shape.
3. **`tmp/menuinterrupt`** — read MENU_PRESENTATION_CENSUS.md first; it is the pass's biggest finding and
   it answers the owner's real question. The WIP carries three new files that are the mechanism half-built
   and never reviewed. The owner does not want a third opt-in: the target is a compile-time guarantee like
   `Tool.paintsOnCanvas`, and the close-out must say plainly whether that was achieved or came out weaker.
4. **`tmp/crosseraser`** — WIP only, no reported design. Re-derive it from the diff.

Then Add Text stage 1b (ADD_TEXT.md; **Stage 2 is already on main and must not be rebuilt**) and the perf
programme's Tier A in PERFORMANCE.md.

**Ask the owner for the third Action Recorder capture early** — a blend-mode `Menu` on the layer rail with
a stroke drawn straight through it. It decides whether the census's 12 unknowns are broken, i.e. whether
the count is 19 or 7, and nothing in the source can settle it. The other two captures (timeline menu,
onion panel) are still worth having.

Four things the owner owes an answer on are listed at the end of HANDOFF.md. Ask when they block work.

---

## Notes for whoever writes the next prompt

**Why fillborder is first and lasso second**, despite lasso being the older ask: fillborder is clean and
small, both touch the fill engine, and whichever lands second pays the rebase. Cheapest order.

**Do not re-run the four stopped workflows.** Their journals hold what each agent returned, including
diagnosis phases whose conclusions never reached a report — paths are in HANDOFF.md, and reading them is
far cheaper than re-deriving. They are session-scoped; read before they are pruned.

**Do not ask the owner to re-check the lasso, the cross eraser or the menu bugs on the current build.**
All four are known broken and they reported every one of them.
