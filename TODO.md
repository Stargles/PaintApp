# TODO

The owner's asks, live. Recorded when they arrive, deleted whole when done **and merged**.
[BUGS.md](BUGS.md) is for what *we* find; [HANDOFF.md](HANDOFF.md) is the checkpoint, never the only
record of an outstanding task. Items marked "(status unclear — check)" were carried from older notes and
could not be verified as open or closed; verify against `main` and `git log`, then delete or fix.

## Queue — the order work happens in (owner, Nov 21: *"communicate better … plan correctly"*)

Every status report to the owner lists this queue with each item's state, not only what is in flight.
"Installed" means the code on `main` — an ask below that is not marked shipped is **not** in it.

1. **Play crash** — in flight (`tmp/nov21-play`): measure the simulator's real backboardd on Test1.
2. **Gallery shows the build** — in flight (`tmp/nov21-version`).
3. **Crash catcher** — in flight (`tmp/nov20-crash`).
4. **Open lasso acts as closed for every action** (Nov 17 ruling) — **never started**; queued behind
   the crash work and not reported. Starts the moment (2) lands (independent code).
5. **Frame steps instant and unstaggered + bake speed** — scheduler stage 2, after (1) merges.
   Folded in (owner, Nov 21): **zooming out after zooming in on a 5000² canvas, the edges appear a
   moment late** — caused by `d72eb69f`'s window-sized pictures (only the visible window is drawn, so
   newly revealed edges wait for a redraw). Owner: minor, fix along the way. Likely shape: keep a small
   whole-canvas picture under the window so revealed edges show at once (soft) until the sharp redraw.
6. **Undo latency / raster Undo budget** — scheduler stage 3 (one memory budget).
7. **Re-check against `main`, then fix what remains:** stroke briefly disappears, stroke latency and
   pan hitches, canvas freezes, rapid-edit whole-iPad failures, Liquify shown while held, Move-exit gap,
   the red `SelectionEditUITests` swatch test.
8. Audit follow-through, streaming on the real link, smaller asks below.

## Current — iPad build `8545ac57` (= `2891caad` code) installed 2026-11-21, owner re-test pending

- [ ] **Owner's check of `2891caad` FAILED (Nov 20, ~22:45, Test1).** Installed build confirmed `2891caad`
  (latest main: includes the window surfaces `d72eb69f` and the To Cross fix `bd52b37f`).
  (a) **Play crashes the app** — still; the 370 MiB simulator gate passed, so the gate does not model
  what kills it. **No crash or JetsamEvent log on the iPad for Nov 20** (the Nov 18 ones exist), so
  this is not an OS memory kill — find out what it is before fixing anything.
  (b) **A frame step takes ~400 ms** and (c) **the drawing layer and the rest of the sandwich arrive
  staggered and look different** — contradicts the claim that steps are instant and unstaggered. Code
  read: `frameStepSettleSeconds = 0.5`; while settling `FrameBaker.image(for:)` returns nil on a ring
  miss (no decode while flipping), and after the settle every layer re-renders its own picture.
  (d) **Orange bars (the bake) take a couple of seconds per frame.**
  (e) **The gallery's version (1.0.43 (1)) never changes** — the owner cannot tell which build he has.
  Show the commit and build date; every build stamps it.
  Owner: *"Please fix everything and do it right. Don't screw up by poor planning and project
  management."* Scheduler (docs/SCHEDULER.md) is not yet started — he asked whether it is.
- [ ] **Owner's check of `e88cba87` FAILED (Nov 18 late).** Owner: *"I have no idea how this ever managed
  to pass through all your tests, and if I caught this, then who knows what I did not catch."*
  (a) **Play → heavy lag, then the iPad crashes** — the *third* time this regression has shipped;
  prime suspect the new frame-change hold (a screen-sized snapshot per frame step, so per played frame).
  (b) **Frame switching is not instant** — owner: frames are already baked, so a step should show the
  baked frame at once; the hold covers the gap instead of removing it.
  (c) **To Cross eraser still slow and the erased strokes flicker back** — recording saved on the iPad
  (newest in Documents/Recordings).
  **Fixed on `tmp/nov19-eraser`, not merged, owner to confirm on Test1:** a To Cross cut changes the
  cut stroke's whole footprint, so one drag's live window grew to most of the 5000² canvas; past 12.6
  million pixels its render was refused on the iPad 9 (192 MiB texture budget), the window was dropped
  for the rest of the drag, the layer's older picture came back (the flicker) and the whole layer was
  re-rendered every 0.25 s under the pen (the slowness). A victim no render had measured did the same.
  Now the window is bounded to what the screen shows at the screen's resolution, an unmeasured victim
  is measured at the cut, and a To Cross drag never falls back to re-rendering the layer.
  `EraserFeedbackUITests` (red on main: 4 layer renders and 1 flicker-back in one drag).
  (d) **Cut and Normal erasers draw no circle cursor**; To Cross does — all three need it.
  **Fixed on `tmp/nov19-eraser`:** every vector eraser mode draws To Cross's ring (Cut and Erase at
  the pen's pressure, To Cross at full size, as each resolves).
  Gap to close with the fixes: no test played a baked scene on a 5000² document at the owner's size and
  watched memory, and none timed a frame step against the baked frame.
  **NEW — the iPad crashes while a 5000² scene is being seeded/opened (Nov 18, 23:33).** The opt-in
  `DeviceStressUITests.testPlayAndStepFiveVectorLayersAtFullSize` (Debug build of the play fix) never
  reached Play: ~34 s in, creating a 5000² canvas seeded 5 layers × 6 frames, backboardd was killed at
  1,850 MiB (`~/PaintWork/nov18-owner-check/crash/JetsamEvent-2026-11-18-233341.ips`, log
  `~/PaintWork/nov18-play-evidence/device.log`). The render-server census gate covers play and steps
  only; extend it to open + first bake + seeding, find the producer, fix, then re-run the device test.
  Likely the same family as Nov 16's "orange bars on entering a document".
  **Found and fixed on `tmp/nov19-open`, not merged, device not yet re-run:** not the seed — every layer
  host showed its cel as a canvas-sized bitmap (95 MiB at 5000²), so entering the scene handed the
  render server 476 MiB of layers plus 47 of onion skin at once, every settled frame step five more,
  every edit and undo one more: 6,825 MiB over the playcheck routine on the iPad 9 simulator. Layers,
  the host's baked raster and the onion skin now reach the server as window-sized surfaces
  (`CanvasPictureView`): 161 MiB entering, ~260 over the routine. Gate: `PlaycheckGateUITests` (the
  owner's routine, budget 370 MiB over the whole session). Still canvas-sized bitmaps: the sandwich's
  live halves and Move bands (blend-mode/effect/transform documents only), the lasso float.
  **(a) and (b) fixed and installed in `2ecc771e`, play not yet confirmed on the device:** the bake reached the screen as a fresh
  95 MiB bitmap per played frame (`belowView.image`) — 10,586 MiB handed to the render server in 12 s
  of playback on the iPad 9 simulator; now a pair of window-sized surfaces (`BakedFrameWindow`), 25 MiB.
  A step is a flip until it settles (`CanvasManager.framesAreFlipping`): it shows the bake, the hosts
  render only once the playhead is still, under the bake; the snapshot hold is deleted. Gate:
  `PlaybackSurfaceUITests` (red on `e88cba87`'s code). Owner to confirm play and steps on Test1.

- [ ] **November 16 iPad test failed (owner, Test1, 5000², 5 vector layers).** Undo lag; the
  circle-and-line Fill gap; rapid draw→Undo and rapid drawing blacked out / restarted the iPad; entering
  a document showed orange bars ~10 s per frame. Owner: *a build this faulty must never reach the iPad;
  fix everything, audit the repo for spaghetti, and keep going without stopping.* Owner's concern is
  less-visible defects of the same kind, so the audit looks for them, not only for structure.
  Lead: three Jetsam events all kill **backboardd at its 1,850 MiB limit** (app 626–816 MiB), so the
  display server is drowning in surfaces the app hands it; every edit re-rasterized a whole 5000² vector
  cel (350–640 ms); bakeComposite 2.2–7.4 s a frame. The Fill test line was Rough Ink at 0.1%,
  pressure-varying. Owner also recalls Fill latency and a crash when rapidly filling several regions.
  **Shipped Nov 17, awaiting the owner's hand test:** render-server pinning and 0.25 s render pacing,
  band-from-memo bake, Undo trim that never wipes history (plus a notice), Fill at scale 1,
  enclosed-ink Fill, Move lift repairing only the lifted footprint, and the recorder now logs tool
  settings (owner: the missing settings were *a failure itself*). **Owner to confirm:** Undo lag, the
  circle-and-line Fill (Mend Gaps with Reach sufficient must cover beneath the line while keeping the
  circle's outer boundary), rapid draw/Undo, orange bars on entering Test1.
- [ ] **Stroke latency and pan hitches on the Nov 17 build (owner, Nov 17 evening, Test1 5000²,
  stream running).** Strokes sometimes lag noticeably and a canvas pan sometimes freezes for a split
  second; owner suspects one underlying lag spike behind both. Owner: *"The main thread should never
  freeze either way."* Recording `recording-20261117-220308` (in
  `~/PaintWork/nov17-lag-evidence/`): main-thread run-loop passes of 113–796 ms every few seconds,
  almost all in `sourcePhase` with no named span accounting for them (named main spans are ≤ 33 ms);
  background `bakeComposite` 5.3–8.8 s per frame and `thumbnailFlatten` up to 794 ms run alongside.
  Find what runs unattributed on main (stream frame handling, bake installs, `renderIsolated` on
  main, IOSurface waits) and move it off; attribute every main-thread span the recorder sees.
  **Found Nov 18 (simulator, WIP `tmp/nov17-hitch` @ `8a7c2bce`, NOTES.md in that worktree):**
  (1) the live eraser re-renders all ink under it **on main** every move (`StrokeScratch.replaceCelContent`
  → `CelContentPicture.rendered`) — one pass down a 5000² × 5-layer scene froze main 6.1 s (Debug);
  draw that window off main into `WindowSurfaceView` like held edits; (2) live stamping
  (`DabImageCache.stamp`, high-quality resample + per-dab brush copy) runs on main — ~17 ms at 6 px,
  550–713 ms per event at big sizes; (3) Core Animation converts every landed picture on main because
  `RasterSurface`'s byte order is not CA-native. Built, not gated: a main-thread stall sampler
  (`mainStall` lines name the code), lift→base `ink` log, the frame bake paused while a touch is down
  (+250 ms), thumbnails at `.utility`. The stroke flicker did not reproduce on the simulator.
  **Installed Nov 18 (`e88cba87`), owner to confirm:** (1) is fixed — the live eraser renders off main
  (big erase 6125 → 265 ms, simulator) — plus the stall sampler and the bake pause. **Still open:** (2)
  live stamping on main; (3) the CA conversion; and the lift's `settleCelContent()` still renders one
  window-sized eraser picture on main when the background one has not landed.
- [ ] **Regression: a stroke briefly disappears after it is laid down, then reappears (owner, Nov 17
  evening, build 9792e799, Test1 5000², Rough Ink).** Owner bets on *"a gap between some kind of
  preview state and a baked state"*; this was fixed once before, so it is a regression — prime
  suspect the Nov 17 render pacing (`DeferredVectorRender`, 0.25 s) / `DisplayPin` changes letting the
  live ink go before the paced base picture lands (`UnlandedInk` exists for exactly this handoff).
  Recording `recording-20261117-225331` (`~/PaintWork/nov17-lag-evidence/`) shows the strokes and
  rasterizes but the recorder does not log the live-ink → base-picture handoff — make it.
  **Same family, erase (owner, Nov 17 late):** erasing a lot at once, the erased strokes briefly
  reappear and then vanish — the old base picture shown again before the erased one lands. Recording
  on the iPad (newest after 22:53). One fix: the live picture stays until the base that matches it is
  on screen, for adds and removes alike.
  **Same family, frame change (owner, Nov 17 late, recorded on the iPad):** changing frames, parts
  of the active layer are drawn over parts of the other layers for up to ~1 s before the frame settles;
  a frame change must look near-instant. Likely regression. Rule for all three: the screen never shows
  a mix of old and new pictures — hold the last complete picture until every part of the new one is ready.
  **Frame-change cause found (different mechanism):** on a frame step the active layer's new cel has
  no cached picture (the iPad 9 budget holds two 5000² renders), so the layer deliberately keeps its
  previous picture — the previous frame's ink — over the new frame for up to ~1 s. Fix: hold the whole
  previous frame, or show the baked new frame, until every layer of the new frame is ready.
  **Installed Nov 18 (`e88cba87`), owner to confirm:** while any layer awaits its first picture of the
  new frame, a screen-sized snapshot of the old frame covers the canvas
  (`InteractionHitchUITests.testSteppingFramesNeverShowsAMixOfTwoFrames`: 8 mixed → 0). The simulator's
  "vanishing stroke" was the test, not the app; the owner's stroke and erase flicker still need his
  check. **Open:** a pan or zoom during the frame hold leaves the cover where it was.
- [ ] **Canvas freeze still recurs.** Flight `flight-20261117-191152` (Test, 2048², same folder): the
  watchdog replaced a stranded `canvas.pan` found `.ended` with 0 touches on `CanvasPlaneView`;
  lifetime repairs now 24. In that flight a two-finger pan's touch was cancelled and began again
  mid-gesture (touch 43 → 44), then `canvas.pan` went began → ended and never back to `.possible`.
  The watchdog repairs it; the root cause is still open — see "Recurring canvas freezes" below.
- [ ] **An open lasso selection acts as closed for every action (owner ruling, Nov 17).** Today an
  open (unclosed) lasso lets Move work but the whole bottom selection bar — copy, duplicate to new
  layer, etc. — does nothing. Owner: *"even if the lasso is open, it should still treat it as a closed
  one. The circle to close it is for if the user wants to make a new selection."* Close the loop
  implicitly (last point back to the start) for every consumer, and remove the Move-only special
  case for open selections, which this makes redundant. Amends docs/LASSO_MOVE.md §5.29 — update it.
- [ ] **`SelectionEditUITests.testTheColourSwatchOpensThePickerOnTheLinesOwnColourAndTheLineFollowsItLive`
  red on an iPad 9 simulator (Nov 17):** `emptyToolbarPoint` finds no 44 pt gap in the portrait
  toolbar — the same stale premise fixed in `GraphEditorFingerUITests` by launching landscape.
- [ ] **Build the real-time scheduler — [docs/SCHEDULER.md](docs/SCHEDULER.md) (rules ruled Nov 17;
  owner delegated them).** "Real time" in the owner's first prompt meant this; it was never built.
  Five stages, each shipped and checked on the iPad. Owner may wait for a larger usage plan before the
  migration (stages 2–5); stage 1 rides on the current hitch fix.
- [ ] **Fix the November 16 audit findings** ([docs/AUDIT-2026-11-16.md](docs/AUDIT-2026-11-16.md), 18
  ranked). Repeating defect: RAM-derived budgets (192 MiB on iPad 9) tested at 2048² that silently
  decline, scale down or drop history at the owner's 5000². Silent refusals: done Nov 17 — artist-facing ones
  already noticed except warp/posed raster (Move, warp, posed bake), which now say "Not enough memory
  to do that"; Liquify's notice still says only "couldn't be prepared". **Open:** the canvas-size ceiling measures the app, not
  backboardd's 1,850 MiB; (`CALayer.contents` installs audited Nov 17: each is one live surface
  per layer; raster thumbnails no longer decode or keep a canvas-sized image); three bitmaps per vector cel; unbounded static caches; commit/un-suppress still invalidates
  `.everything`; `renderIsolated` on the main thread. Add a gated 5000²×5-layer fixture for every budget
  consumer (`DeviceStressUITests` is the device half).
- [ ] **Raster Undo at 5000² is one whole-cel step (190.7 MB) against the iPad 9's 192 MB budget**, so
  raster layers keep only the protected minimum of history. Price raster steps by dirty tiles, as vector
  steps already are (0.11 MB a stroke).
- [ ] **Fix severe Undo latency.** Owner: drawing is responsive on the latest Release, but Undo still has
  *"enormous latency"*. Do not start another broad audit or testing/storage framework. Leads: settled
  Undo's clipped repair copies a full image (~95 MiB per 5000² bitmap; PERFORMANCE.md §11.11b); On Top
  stream surface work and vector rendering shared one serial queue, so a stream job waiting up to 500 ms
  for an IOSurface could delay a settled Undo (a separate stream worker is in the source — check on the
  iPad whether that was the delay Kevin saw). Simulator controls showed no stream-only excess and cannot
  measure physical latency. On the iPad: one Undo per quiet interval, stream off vs a moving On Top
  stream, counting rasters and timing tap to ink disappearance; use the recorder to pair an Undo press
  with the accepted base picture. Change the renderer only if that comparison supports it.

## Open reports and asks

- [ ] **The auto-resigner broke again — "PaintApp is no longer available" (owner, Nov 20; ~10th time).**
  Owner: *"Fix it well and fix it once. Remember the iPad might be locked, or the Mac might be off … When
  the Mac is on and the iPad is unlocked it should automatically trigger so I don't have to tell you."*
  **Merged and live Nov 21** ([docs/RESIGN.md](docs/RESIGN.md)): sign (Mac only,
  generic destination, fetch best-effort) and install (iPad only) are separate stages over one state
  file; a 5-minute user LaunchAgent plus the hourly root daemon's wakes; script tracked in
  `tools/resign/`, pinned by `install.sh`, 14-case harness. Open: confirm the first real expiry (Nov 28 03:31 UTC) renews unattended.
- [ ] **Catch iPad crashes without the owner (owner, Nov 19).** *"I shouldn't have been the one to catch
  that iPad crash."* The app cannot catch a backboardd Jetsam in-process, but: (1) on launch, detect that
  the last session ended uncleanly and save the flight recorder's last 90 s (persist it periodically so a
  kill doesn't lose it) plus a "the iPad crashed last time" note; (2) MetricKit exit/crash diagnostics;
  (3) a Mac-side pull of new `JetsamEvent-*.ips` / app crash logs via `devicectl` whenever the iPad is
  reachable, flagged in the next session.
  **Owner rulings (Nov 20):** on reopen after a crash show a **small fading notice** ("The app didn't
  close cleanly last time — a crash report was saved"), report listed under Recordings in Settings. The
  Mac pulls the iPad's crash logs **only when the owner asks** — no change to the hourly resign job; a
  `tools/` script makes the pull one command.
  **Status (Nov 20, branch `tmp/nov20-crash`, not merged or installed):** built — `UncleanExitWatch`
  (foreground marker + persisted flight ring, promoted to `Recordings/crash-*.jsonl` on a launch that finds
  the last run died in the foreground; a backgrounded end reports nothing), MetricKit diagnostics written as
  `metrickit-*.jsonl`, the fading reopen notice (the flight badge's capsule, also drawn on the gallery), and
  `tools/pull-ipad-crashes.sh`. Armed on the simulator only by `-uiTestCrashWatch`. Owner to confirm on the
  iPad after the next install (a force-quit from the switcher is a background end and rightly reports
  nothing; a real backboardd Jetsam or Xcode's Stop while drawing is what raises it).
- [ ] **Intermittent whole-iPad failures during rapid edits.** Owner: black screen and brief restart
  during draw → Undo → draw; also a crash after repeated Fill (Nov 11); Kevin confirms **rapid To Cross
  erasing on Test1 (4096²) triggers the failure**. Coincided with rapid activity and a running stream.
  Compare the same workload with and without a stream; check native stream-host rebuilds first, Fill's
  full-size reference image (~95 MiB per pass when a stream is in the reference) and preview-to-base
  handoff. Owner expects baked scenes to keep working memory bounded. A Nov 13 SystemMemoryReset report
  names no killed process. Preserve exact Fill pixels; measure before naming a cause. Possibly related to
  the 1,850 MiB backboardd finding above.
- [ ] **Show vector Liquify while the stroke is held.** Owner: the iPad only shows the reshaping after
  lift. Points should follow the gesture live, with exterior ink fixed and raster / linked in-between
  behaviour preserved. Live-preview fix is installed; **real-Pencil confirmation is open.**
- [ ] **Find and fix the cause of recurring canvas freezes.** The watchdog is recovery, and the owner
  says recovery is temporary: establish where touch ownership or recognizer lifetime goes wrong, fix
  that, then remove the watchdog code, state, messages, tests and docs cleanly (keep independent
  diagnostics). Intermittent; a short clean device run is not resolution. Kevin wants it fixed from
  existing evidence, otherwise the automatic recorder must gather decisive evidence *without asking him
  to reproduce, start Record My Actions, save another flight, or run more manual tests.* Leads: UIKit
  cancels one contact of a moving two-finger gesture and reissues it ~10 ms later without pinch /
  rotation / stroke bindings (repair #23); a Nov 11 sequence loses all four recognizers on the next
  admission after pinch/rotation fail at lift; a previous lift's watchdog can evaluate a newer gesture.
  The automatic recorder saves both patterns plus a moving pair with sound bindings and unchanged view.
  Retrieve new automatic flights independently. Root cause is open.
- [ ] **Confirm the one-tap Move report in Test.** On a saved scene, lasso visible vector ink and tap Move
  once; the untouched box stays up; one Undo cancels the zero-nudge lift. Use a disposable copy for a
  drag or Set Down. Also verify older physical workflows on real scenes (clipboard menus, Mend All Fills,
  saving and recovery).
- [ ] **Move-exit gap.** Owner prefers the lifted drawing stays visible until the compositor's finished
  picture shows; stream displacement happens after release or Set Down. (Status unclear — check whether
  the shipped Set Down continuity covers it.)
- [ ] **Windows streaming on the real link** — see (27) below. Tailscale showed the laptop online but SSH
  rejected the key on Nov 14; the stream host's TCP accept can replace an active iPad, so probe only from
  the real desktop session with Kevin, and avoid hosts that repeatedly prompt for firewall access. Do not
  poll an unreachable host. Qualify bounded Windows discovery (DNS name limits) on the real host too.
- [ ] **Deferred: view previous crash reports in the app**, like recordings. Owner: *"at some point if it
  is possible."* Wait until requested.
- [ ] **Old saved Views can hide a group's descendants** when last saved with the group visible (old writer:
  Hide → Add View → All → Save). Repair each saved visibility state in the one-shot migration; keep the
  current-format guard. (Status unclear — check; a fix `d5ff1463` was reported passing.)
- [ ] **Retire the inline legacy migrations** (compositor Input A/B slot ranking; pre-group-property
  marker) through the one-shot package repair, preserving Projects/Backups/Trash and order, then delete
  the decoder branches. No new permissive decoder route. (Status unclear — check.)
- [ ] **Bound stream timing storage between displayed pictures:** keep only count, total and max in the
  existing measurement owner, preserving cadence and log output. (Status unclear — check.)
- [ ] **Smaller audit findings from October 29 (status unclear — check each against `main`):** shape
  handles divide by a non-positive canvas scale during a tiny pinch (reuse the object overlay's guard);
  `AddMenu.primePhoto` silently swallows photo import failure (reuse the existing menu notice); a placed
  picture saved at scale 2 reloads at scale 1; Release UI-test target should build only the active
  architecture; curve-flattening step count converts an unbounded length before its 64-chord cap (fix
  reported harvested); compiler-warning triage (259 occurrences, 182 distinct rows — not 182 bugs; no
  blanket `nonisolated(unsafe)`, no scheduling changes without tracing callers).
- [ ] **Architecture audit follow-through (status unclear — check).** Owner, 2026-10-24: *"codebase
  cleanliness and good architecture as well as performance is a priority"*, *"refactor things that are
  messy and also find and fix bugs"*, *"Zombie code or bloat … should be dealt with. Dont be afraid to
  prune."* Root causes, remove superseded paths whole, design for a 300–1000-cel window/byte budget,
  measure claims. Findings are in docs/ARCHITECTURE_AUDIT.md; most source was reported implemented
  (library relocation / Trash ownership, export cancellation, mask and video budgets, raster residency,
  bounded stream writer, brush preview cache, curve drag, Mode1 eraser seed handoff, text restoration,
  graph capacity, effect numeric domains). Whatever final-source gates were never run should be run once
  on `main`, not re-narrated here. Mode3 (To Cross) per-sample full-base work was replaced by the
  admitted window; final Release cost and the crash cause remain unmeasured.
- [ ] **macOS prompts for ChatGPT access to OneDrive / other app data** (owner saw them; cause unproved).
  Keep scope to the repository, PaintWork and owned-simulator paths; do not scan cloud folders or change
  privacy settings. (Status unclear — check.)

**Owner working rulings that outlive any item:** an owner report lands here before any worker starts;
a blocked release must not stop other open work (run independent tasks in parallel); root causes, not
workarounds; old files are repaired once by a throwaway script and the decoder knows only the current
format (below).

---

## (27) Stream the computer's screen as a layer

Built through stage 4 ([STREAM.md](docs/STREAM.md)): the Windows streamer (`streamer/`, the
`PaintStreamer` task on `desktop-cbr0fl6`), the iPad stream layer, the bar with Freeze / Bake Frame,
files both ways. **Remaining is stage 5 on the real link, with the owner at the laptop.** The owner's
brief (2026-09-13), as it still constrains: stream the Windows screen as a layer live (Blender
rotoscoping, moving the camera, continuing); a Windows-side drop box for images/videos and, if possible,
iPad export back to the laptop; the stream tool under actions, one layer holding the stream object; an
options bar with Freeze and Bake Frame (Bake splits the cel and replaces the stream with an image of that
frame); *low latency, must not lag the main thread*; movable with the Move tool; *many screens or one
specific app*; a streamer designed so it could one day merge into a Windows build of the paint app; the
computer may be turned off and on mid-session; *"stream layers actively moving do not have to be
rendered."*

- [ ] Owner streams Blender to the iPad and rotoscopes over it; source switch, window close, laptop lock
      and reboot behave as STREAM.md §4.5 / §2.8 say.
- [ ] End-to-end latency measured on the real link (a clock on the laptop screen beside the iPad); tune
      bitrate/GOP if needed; numbers into PERFORMANCE.md.
- [ ] The redraw tick's cost measured on the iPad (STREAM.md §8: the `ScreenStream` log line or the bar's
      `streamBar.tickSummary` marker).
- [ ] Owner-verified: Ctrl+V of a bitmap into the drop box (not exercisable over SSH).

---

## Deferred by the owner — written down, not work

- **(22) Select multiple cels at once.** Deprioritised 2026-09-07. The menu row exists, disabled; no
  cel-selection state exists.
- **(10) Linear light as a blend-mode option.** Deprioritised. No colour-pipeline setting exists. (The
  Oklab strand, "(10a)", shipped.)
- **(37) Brush engine stage 12 — `.abr` / Procreate `.brushset` / Clip Studio `.sut` importers.**
  Owner, 2026-09-06: *"skip the importer for now."* Dropped; do not reopen. Owner-side: their tuning pass
  over the other nineteen presets and a real-Pencil tilt test. BRUSH.md §13 holds nine open questions.

## Later — the long-term features

None is designed; each needs its own conversation with the owner before it starts.

- **(28) Audio.** Its blocker is gone (`PlaybackClock` shipped); no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met.
- **Interpolation overhaul.** Owner, 2026-10-22: *"Interpolation will probably be overhauled sometime
  soon so it works better. I'll let you know in the future."* Do not research or implement it now.

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.

---

## How to read and keep this file

Items are in queue order. An item leaves **whole** when it is merged, not when a branch exists — owner,
2026-09-06: *"Basically I want to be able to read the tasks on TODO clearly without already finished
tasks."* Write what the artist sees or wants, the current lead, and the owner's own words where they
constrain the fix; what happened this pass belongs in `git log` and HANDOFF.md. Receipts, gate counts and
evidence paths do not belong here. Check an existing item before adding one in different words. Cite a
symbol, not a line number. Three in flight at once unless the extras need no simulator. Verify a status
before trusting it, including this file's own. A bare item number in a spec or code comment may name an
item that has already left; `git log` resolves it — do not re-add a finished item to make a citation work.

**Old files are repaired once, never read forever.** Owner, 2026-10-10: *"I will still keep the rule of no
legacy code. If an update causes existing files to be outdated, then they should be automatically
repaired by a throwaway script the session makes."* A format change ships a one-shot repair of the
owner's Projects, Backups and Trash at launch; the decoder knows only the current format; the repair is
deleted once the owner confirms their files are repaired.

The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1 (the owner works at 2048×1024, though the
Nov 16 test scene is 5000²).
