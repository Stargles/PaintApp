# Handoff

## Start the next session — Claude Code

From `/Users/juliapark/Desktop/Kevin.P/PaintSoftware`, use this prompt:

> Continue PaintSoftware from HANDOFF.md. Read AGENTS.md, CLAUDE.md and the top of TODO.md; verify
> `main` equals `origin/main`. Usage is tight: one worker at a time, Sonnet unless the task needs Opus,
> short briefs, no re-reading of what HANDOFF already says. Follow "Resume here" below.

## Resume here — November 18, 2026 (weekly limit reset; owner approved the scheduler + memory budget, staged)

1. **Ready to ship: `tmp/nov18-eraser` at `cfcea918`** (worktree `~/PaintWork/PaintApp-nov18-eraser`; it
   contains all of `tmp/nov17-hitch` — delete both branches at merge). On it: main-stall sampler; bakes and
   strips pause while a touch is down (+250 ms); the live vector eraser renders off main (big erase 6125 →
   265 ms on the sim); the stroke-handoff test fixed (the "vanishing stroke" was the test); **frame-change
   fix** — while any layer awaits its first picture of the new frame a screen-sized snapshot of the old
   frame covers the canvas, so the screen is wholly old or wholly new (`InteractionHitchUITests.
   testSteppingFramesNeverShowsAMixOfTwoFrames`: 8 mixed → 0, mutation-checked). All 5 InteractionHitch
   tests pass alone; EraserOffMainLogicTests 3/3; VectorEraserHybridLogicTests updated for the off-main
   eraser (a refused source is now found at the lift's settle, not by `replaceCelContent`'s return).
   **A final Debug + Release fast-tier gate was running** (`~/PaintWork/nov18-gate/gate.sh`, output
   `~/PaintWork/nov18-gate/gate.out`, ends with `GATE-DONE`; it deletes its own simulator). If it is not
   finished, wait on it with one blocking command; if it never printed GATE-DONE, re-run the script.
   Pass = 0 failed in both. Then: rebase the branch onto `origin/main` (main is ahead by docs only), build
   the signed Release for the device from the rebased head, install, update resign_state with that SHA,
   merge `--ff-only`, push, delete the worktree, both branches, `~/PaintWork/nov18-*` and
   `~/PaintWork/nov17-*` evidence, then ask the owner for the 2-minute check. Record in TODO.md as open:
   a pan/zoom during the frame hold leaves the cover where it was; the lift's `settleCelContent()` still
   renders one window-sized eraser picture on main when the background one has not landed.
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
5. **Scheduler (owner said go, 2026-11-18):** after this install, stage 2 = an Opus design page reviewed before code, then the core + R1 migration; stage 3 = one memory budget + a reuse pool for canvas-sized pictures; then stages 4–5. Usage-aware: clear context between stages,
   since a fresh context is cheaper than a long one. Every change must keep its rules.

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
