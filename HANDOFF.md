# Handoff

## Start the next session — Claude Code

From `/Users/juliapark/Desktop/Kevin.P/PaintSoftware`, use this prompt:

> Continue PaintSoftware from HANDOFF.md. Read AGENTS.md, CLAUDE.md, TODO.md and BUGS.md and verify
> `main` equals `origin/main`. Start with the owner's re-test of the November 17 build on their
> iPad (Test1: Undo lag, circle-and-line Fill, rapid draw/Undo, orange bars on entering). Then the
> twelve UI tests red on old `main` too, raster Undo pricing, and the open audit findings in
> TODO.md. Use focused delegation, keep TODO.md and HANDOFF.md current, and brief the owner in
> terms of what they see in PaintApp.

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
