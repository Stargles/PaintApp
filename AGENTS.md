# AGENTS.md — start here

For any coding agent working this repo (Claude Code, Codex, or another). PaintSoftware is an iPad
paint and animation app (SwiftUI + Metal) with a Windows screen streamer beside it (`streamer/`).

## Read, in this order

1. [HANDOFF.md](HANDOFF.md) — the state of the repo and what to do next. Its first section is the
   prompt that starts a session.
2. [CLAUDE.md](CLAUDE.md) — the build, test, merge and deploy rules. **It is named for Claude Code but
   binds every agent**: worktrees outside `~/Desktop`, the shared simulator, the fast tier, the
   triage rules, the deploy steps. Where it names a Claude-only tool (subagents, the interactive
   simulator control, workflows), an agent without it drives gestures through XCUITest and works
   serially; everything else applies as written.
3. [TODO.md](TODO.md) — the owner's asks, in queue order. [BUGS.md](BUGS.md) — what we find.
4. The specification for whatever you pick up, under [docs/](docs/) (CLAUDE.md's "Docs" section maps
   them). [PERFORMANCE.md](PERFORMANCE.md) before optimising anything.

**Verify the handoff before trusting it**: `git fetch origin`, `git worktree list`, and for every
`tmp/*` branch `git log --oneline origin/main..<branch>`. A session cut off mid-task commits to its
own branch, so `main`'s HANDOFF.md can be behind.

## The owner, and how to work with them

- **The owner (Kevin) is an artist and the product owner.** He does not read the code; he judges
  behaviour. His device is an **iPad (9th generation) in landscape, 1080×810 pt** — the UI suite runs
  portrait on a 13" simulator, so screenshot anything visible at his size too, and brief performance
  in counts (publishes, passes, pictures), not simulator milliseconds.
- **Ask in plain language, with 2–4 concrete options**, one decision per question; name what the
  artist sees, and define any term the code or a spec invented. Never bury a decision in a summary.
- **His observations and theories are evidence.** They have beaten careful code tracing several
  times, on cause and on design. Test his theory first; a duration he reports that matches a code
  constant is near-proof.
- **When a choice costs appearance, render the A/B and send the images** — he has reversed rulings on
  seeing what he had accepted on reading a number.
- **A feature asked for "later" is written down, not researched.**
- **Record before you act**: every report or ruling lands in TODO.md (and HANDOFF.md if the next step
  changes) *before* work starts, and both are re-checked after every merge. A session can end at any
  moment; what lives only in a conversation is lost.
- **His usage budget is set per session** (how many agents, which models). Ask if it was not stated;
  put cheap models on mechanical work.
- **A real scene is 300–1000 drawn cels.** Design memory around a window or budget, never "load it
  all" (he named the YouTube-buffer shape himself).

## Standing engineering rules

- **Clean modular architecture is the top priority.** No clutter, no zombie, unused or legacy code.
- **Solve the root cause**; if the cause is a bad structure, refactor it. Never bolt a fix on top.
- **Reuse and extend what exists**; never build the same thing twice. Take nearby clean-ups in scope.
- **Remove cleanly**: a deleted feature leaves no vestigial parameter, half-live control or "this used
  to be" comment. When a ruling replaces shipped behaviour, the old path goes whole — code, branches,
  strings, tests, doc text — before the new one is built on the same seam. No flag gating old vs new.
- **His scenes are real.** A saved-format change ships a **one-shot repair** that rewrites existing
  packages (Projects, Backups, Trash) at launch; the decoder knows only the current format and fails
  loudly — never a `try?` or a default that reads unreadable data as empty. The repair is deleted once
  he confirms. Round-trip against a package the previous build wrote.
- **A brief's premises are hypotheses.** If the code says otherwise, say so and do the right thing,
  or stop and ask if it needs a ruling.

## The bar for done

1. Root-cause change, with logic tests; mutation-test each new assertion (break the code, see it go
   red, restore) — commit first, mutate second.
2. **Drive it**: a cold-start XCUITest that reaches the feature the way the artist would and asserts
   what is **drawn or exposed**, not only a stored value; plus a screenshot you actually look at.
3. The fast tier (CLAUDE.md's command verbatim, your own simulator) green in **Debug and Release**,
   its `totalTestCount` reconciled against a static `func test` count; `tools/check-ui-identifiers.py`
   and `tools/check-ui-helpers.py` clean; the UI classes you touched run by `-only-testing:` (resolve
   the **class**, not the file name). A new test file is added to `project.pbxproj` by hand — check for
   duplicate ids.
4. Before a device install, drive the old things too (a scene plays, a pan from the grey, a Move box
   and a graph node dragged and released, a stroke).
5. Say plainly what was **not** run. The full UI suite is not run per item.

## Git, simulators and the machine

- One worktree per task under `~/PaintWork/PaintApp-<id>` on `tmp/<id>` from `origin/main`. Merge
  with `git -C /Users/juliapark/Desktop/Kevin.P/PaintSoftware merge --ff-only tmp/<id>` — **never `cd`
  into the worktree to merge** (it merges the branch into itself and prints "Already up to date");
  verify with `git log --oneline -1` on main.
- In the same merge, delete your finished item **whole** from TODO.md. On a TODO.md rebase conflict,
  apply your removals to origin's copy — never keep your own copy (it resurrects finished items).
- No `git stash` (one stack for every worktree). Never reset to `origin/main` (a shared ref) — only to
  a sha you recorded.
- `.git/hooks/post-checkout` rebuilds the graph and dirties the tracked `graphify-out/GRAPH_REPORT.md`
  on every branch switch, which blocks an `--ff-only` merge in that tree.
- Your own simulator for every run (`xcrun simctl create`), deleted when done; wrap `xcodebuild test`
  in `tools/simlock.sh`; `-parallel-testing-enabled NO` except for the full suite. Never `simctl
  shutdown all`, never kill by process name.
- Wait by blocking on one condition in a single command
  (`until grep -qE "TEST SUCCEEDED|TEST FAILED|BUILD FAILED" log; do sleep 20; done`), never by
  re-running a check.
- A device test needs the iPad unlocked ("Timed out while enabling automation mode" is the lock
  screen, reported as a test failure).

## Reporting back

Short. Per item: the root cause, what changed (files and symbols) and what was deleted, the merged
sha, the fast-tier counts (Debug and Release), the UI tests added and run, what you drove and saw,
what the artist does next at each step, anything in the brief you refuted, and any owner question —
in plain language with 2–4 options.
