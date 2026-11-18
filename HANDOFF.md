# Handoff

## Start the next session — Claude Code

From `/Users/juliapark/Desktop/Kevin.P/PaintSoftware`, use this prompt:

> Continue PaintSoftware from HANDOFF.md. Read AGENTS.md, CLAUDE.md and the top of TODO.md; verify
> `main` equals `origin/main`. Usage is tight: one worker at a time, Sonnet unless the task needs Opus,
> short briefs, no re-reading of what HANDOFF already says. Follow "Resume here" below.

## Resume here — November 17, 2026, late (written at 94% weekly usage)

1. **An Opus worker was fixing the owner's three newest reports** on branch `tmp/nov17-hitch`, worktree
   `~/PaintWork/PaintApp-nov17-hitch` (evidence `~/PaintWork/nov17-hitch-evidence/`): main-thread
   hitches while drawing/panning (stroke lag, pan stalls — the 5–9 s frame bake competing; it is
   docs/SCHEDULER.md stage 1), strokes vanishing briefly after lift, erased strokes reappearing
   briefly, and (if same cause) the active layer drawn over others for ~1 s on a frame change — one
   rule: never show a mix of old and new pictures (TODO.md). If the session was cut off, the worktree and its commits
   survive: `git -C ~/PaintWork/PaintApp-nov17-hitch log --oneline origin/main..` and `git status`
   there show what it reached. Finish only what is missing (Sonnet if it is just tests/gates).
   The owner's recordings are in `~/PaintWork/nov17-lag-evidence/`.
2. **Then gate and install:** Debug + Release fast tiers on an own iPad 9th-generation simulator,
   the UI classes the change touches, then the CLAUDE.md "Deploy to iPad" steps from the worktree
   (UUID only), update `~/.config/paintapp/resign_state`, merge `--ff-only` from the Desktop
   worktree, push, delete the worktree/branch/simulator/evidence (owner: keep storage lean). `main`
   already carries, uninstalled: the graph-editor axis-lock fix, the memory-refusal notices, the
   thumbnail fix and twelve repaired UI tests — they ship in that same install.
3. **Next owner ask, queued:** an open lasso acts as closed for every bottom-bar action (TODO.md item;
   remove the Move-only open-lasso path).
4. **Before calling any build done:** a full UI suite run on an iPad 9 simulator (Mac time, few tokens —
   read counts only), and the owner's 2-minute check on the iPad: draw, erase a lot, Undo, pan, change
   frames, play, fill. Pause new features until the mixed-picture fix is installed.
5. **Scheduler:** docs/SCHEDULER.md is ruled (owner delegated the rules); stages 2–5 wait for the owner,
   who may get a larger plan first. Every change must keep its rules.

## Sign-off — November 17, 2026, Toronto

- **The November 16 failures are fixed on `main`** (TODO.md's first item has the list): the
  display server is no longer handed a canvas-sized picture per edit (the backboardd Jetsam
  behind the black-outs), the bake reuses its band memo (orange bars), Undo trims history to its
  budget with a notice instead of wiping it, Fill covers ink enclosed by the region (the owner's
  circle-and-line), the recorder logs tool settings, and a Move's lift repairs only what was lifted.
- **Gates at `d08d18a5`:** Debug and Release fast tiers 5,679 passed + 4 skipped each; the first
  full UI run (on the 13" simulator, which fails the 1080×810 size premises — use an iPad 9th
  generation simulator for the UI suite) left 33 reds; re-run serially on a fresh iPad 9 simulator
  with the one extra Fill red the worker found, 12 remain and all 12 are red on old `main` with
  the same message (TODO.md item). Four Fill regressions found on the way were fixed in `10f65379`.
- **Device stress on the owner's iPad passed** — `PaintSoftwareUITests/DeviceStressUITests.swift`,
  opt-in with `PAINTAPP_DEVICE_STRESS=1`, creates and trashes its own `ZZ-stress-*` folder and
  scene, never resets settings or libraries. Log: `~/PaintWork/nov17-device-stress/device-run3.log`.
- **Installed on the iPad 2026-11-17 (Toronto, evening)**: signed Release `9792e799` (binary UUID
  `0A93A076-21CE-329D-88CE-1FFC3BE90D1B`, profile through Nov 20 07:09 UTC) from
  `~/PaintWork/crash-20261111/device-fresh-9792e799-Release/`; `resign_state` updated. The integrated
  `tmp/*` branches, old evidence, archives and old session simulators are deleted (owner: keep it lean).
- **Lessons:** the Release optimiser may free a never-read `var` at its last use — hold test pins
  with `withExtendedLifetime`; on the real iPad the number pad covers the size fields, so a device
  harness hides the keyboard between fields; "Timed out while enabling automation mode" is the lock
  screen.

TODO.md tracks outstanding work and owner rulings. Older checkpoints are in `git log -p HANDOFF.md`.

## Resume rules

Read AGENTS.md, CLAUDE.md and TODO.md. Keep this checkpoint current and keep tasks in TODO.
Use task-appropriate model and effort. Delegate coherent work through verification where it saves
effort. Run quick checks directly and avoid redundant handoffs or reviewer agents. Root owns
priorities, acceptance, the shared native lane and release decisions.
