# Handoff

## Start the next session — Claude Code

From `/Users/juliapark/Desktop/Kevin.P/PaintSoftware`, use this prompt:

> Resume PaintSoftware from HANDOFF.md. Read AGENTS.md, CLAUDE.md and the top of TODO.md; verify
> `main` equals `origin/main`; follow "Resume here".

## Resume here — November 27, 2026 (evening, Toronto)

1. **On the iPad:** `eb58e751` (S3b) installed. Its profile expires 2026-11-28 03:31 UTC; the
   auto-resigner should sign a fresh build from `main` before then — confirm in
   `~/.config/paintapp/resign.log` that it did, unattended.
2. **Merged on `main`:** scheduler S1, S2, S3a, S3b (in-place layer-picture repair, kept-pixel Undo,
   queued second Fill tap), the stroke-flicker fix, the installer's foreground-marker check, and the
   compacted CLAUDE.md/TODO.md.
3. **In flight — S4, the memory manager:** branch `tmp/nov27-s4`, worktree `~/PaintWork/PaintApp-nov27-s4`,
   simulator `E1DB1A4B-4CB2-4E7F-A97D-31A7F552D223`, evidence `~/PaintWork/nov27-s4-evidence/`. Its
   `NOTES.md` is the state. Done: one-eviction-order budget (`NextUse`/`ComesBack`), Undo's 192 MiB cap
   folded into the budget, CG shrink-copy counted (`BakedFrameWindow.shrinkFilter`), bake starvation
   fixed (reserve = room an answer can reach), the 10 fast-tier failures resolved (7 stale tests, 3 real
   bugs); Debug fast tier green (5795); playcheck GREEN once (app peak 1,021 MiB). **Open:** late answers
   read 134 vs base 32 — taken hours apart under unknown machine load, so possibly contention; a worker
   was told to A/B base and S4 interleaved with CPU idle recorded. If it reports no real regression or
   fixes one: Release fast tier, playcheck ×3, the touched UI classes alone on an erased device, drive
   the app, remove `-uiTestAllocationLedger` from `PlaycheckGateUITests`, "S4 as built" in
   docs/SCHEDULER_DESIGN.md + TODO 5/6/9, delete `NOTES.md`, rebase, merge, release.
4. **Then, in order:** S5–S9 (docs/SCHEDULER_DESIGN.md §6), Liquify (TODO 11), Puppet Warp as a Move
   mode (TODO 12), triage of the pre-existing UI reds (TODO 7; the two `FillLiveAdjust` reds are among them).
5. **Release:** `git worktree add ~/PaintWork/PaintApp-rel -b tmp/rel origin/main`, then
   `bash ~/PaintWork/rel.sh` (the script is not executable; it gates, signs, stages and cleans up).
   The installer puts a staged build on once the app has been in the background for 120 s.
6. **Owner checks pending:** frame steps, the open lasso, freezes, stroke flicker, Play on Test1
   (Test1 AirDrop still to come).

## How to work (owner rulings, 2026-11-27)

- Global rules in `~/.claude/CLAUDE.md` bind every session: pace against the 5-hour window only;
  a hook refuses to wake an agent over 200k tokens with a cold cache; subagents cache for 1 hour;
  worker hand-offs follow the seven-part NOTES.md checklist and are deleted once used.
- The orchestrator runs mechanical checks itself (fast tiers, playcheck, solo UI classes, reading
  result lines) — waiting costs it almost nothing — and sends workers only design work and failures.
  Brief workers to read narrowly: S4's first worker spent ~200k tokens reading before editing.
- The owner uses this Mac too: record CPU idle with every timing run and compare builds A/B
  interleaved; never assume quiet or busy.
- Every reply the owner sends costs usage: state scope and exclusions up front; ask only real decisions.
- Some old wait shells are frozen with SIGSTOP on purpose (ending them wakes finished agents); leave them.

TODO.md tracks outstanding work and owner rulings. Older checkpoints are in `git log -p HANDOFF.md`.
