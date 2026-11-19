# Handoff

## Start the next session — Claude Code

From `/Users/juliapark/Desktop/Kevin.P/PaintSoftware`, use this prompt:

> Continue PaintSoftware from HANDOFF.md. Read AGENTS.md, CLAUDE.md and the top of TODO.md; verify
> `main` equals `origin/main`. Usage is tight: one worker at a time, Sonnet unless the task needs Opus,
> short briefs, no re-reading of what HANDOFF already says. Follow "Resume here" below.

## Resume here — November 18, 2026 (late)

1. **Installed on the iPad 2026-11-19: signed Release of `tmp/nov19-open`** (see `resign_state`).
   Every layer, the onion skin and the bake now reach the render server through window-sized surfaces
   (`CanvasPictureView`, `BakedFrameWindow`): the owner's whole routine hands it 283 MiB instead of
   6,825 (iPad 9 simulator). The install gate is `PlaycheckGateUITests` (~4 min, budget 370 MiB, derived
   from one crash, not a device measurement). Not run: full UI suite, device test (iPad locked).
   Next, after the usage window resets: TODO.md's eraser items (c) To Cross slow + flicker and (d) the
   circle cursor for Cut/Normal; then the crash-catcher ask. Still canvas-sized: the sandwich's live
   halves, the Move bands and the lasso float (only with blend modes/effects/transform layers).
2. **Owner's 2-minute check is next:** draw, erase a lot, Undo, pan, change frames, play, fill. TODO.md's
   "Current" section names what each item is waiting for him to confirm, and the leftovers still open.
3. **Next owner ask, queued:** an open lasso acts as closed for every bottom-bar action (TODO.md item;
   remove the Move-only open-lasso path).
4. **Scheduler (owner said go, 2026-11-18):** stage 2 = an Opus design page reviewed before code, then the
   core + R1 migration; stage 3 = one memory budget + a reuse pool for canvas-sized pictures; then stages
   4–5. Clear context between stages. Every change must keep docs/SCHEDULER.md's rules.
5. The Mac may be busy with the owner's own work — check running processes before any timing run.

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
