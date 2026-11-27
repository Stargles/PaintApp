# TODO

The owner's asks, live. Recorded when they arrive, deleted whole when done **and merged**.
[BUGS.md](BUGS.md) is for what *we* find; [HANDOFF.md](HANDOFF.md) is the checkpoint, never the only
record of an outstanding task. "(status unclear — check)" means verify against `main` and `git log`,
then delete or fix.

## Queue — the order work happens in (owner, Nov 21: *"communicate better … plan correctly"*)

Every status report to the owner lists this queue with each item's state, not only what is in flight.
"Installed" means the code on `main` — an ask below that is not marked shipped is **not** in it.
Numbers are stable; a gap is a finished item.

1. **Play crash** — the cause was the **app's own memory** (1.9–2.5 GB on the simulator against the iPad
   9's 1,850 MiB app limit), not the render server. Fixed and installed (`adc8e327`, Nov 25), owner to
   check on the iPad; `tools/playcheck.sh` GREEN, app peak 1,138–1,142 MiB against the 1,165 gate.
   `Engine/MemoryBudget.swift` is the one admission point (888 MiB on the iPad 9; derivation in its header
   and PERFORMANCE.md §37). **Thin spot: Undo** — ~250 MiB the budget is not asked about, 23 MiB under the
   gate; attribute it before an install (with (6)). Five resident 5000² layer pictures are kept (477 of the
   888 MiB): they are what Undo repairs, a bake of the shown frame reads and a pan redraws from. A scene
   with more 5000² layers than fit (≈ 6 with a bake) refuses the extra pictures rather than being killed;
   serving the unedited layers from one composite is the next step if a real scene needs it — owner to say
   whether Test1 grows past five layers.
4. **Open lasso acts as closed for every action** (Nov 17 ruling) — merged and installed; owner to check:
   draw an open C, then Copy, To New Layer, Clear.
5. **Scheduler build, S1–S9 (docs/SCHEDULER_DESIGN.md, merged Nov 25; owner rulings §7 pending).**
   **S1 merged, installed (`fe69a7c0`)**: scheduler core, frame reads as R1, one presenter swapping whole
   picture sets. MEASURED (iPad 9 sim, app clock): tap → whole frame **324–347 ms → 39–94 ms** at 5000²,
   **18–27 ms** on 2048×1024. Owner to check on the iPad: step and scrub a baked scene.
   **S3a merged (`ee72796b`), staged**: R1 producers on the scheduler; seven queues and `Pacing` deleted.
   Gate green (app peak 1,108 MiB); R1 `late` 37 (whole-layer renders — S3b's job).
   **Owner ruling Nov 26: a second Fill tap while the first is still drawing is QUEUED** (no pause, lands after the
   first; never dropped). Today's `waitForFillWork()` on main goes — S3b.
   **S2 built on `tmp/nov25-s2`, NOT merged — gate GREEN since the onion skin joined the budget.** The red was not
   the half level's own memory: at the undo peak the app sits ~300 MiB above what the budget holds on main and S2 alike
   (MEASURED); the half frames merely fill the budget's slack that main's 95 MiB frames left. The onion ghost (48 MiB)
   is counted now; bake encode streams to disk. Window draws are not a regression: playback ~24 flips/s (main ~11/s).
   **Owner ruling Nov 26, built: kept bakes live INSIDE the scene package** (`<package>/bakes/`; shares, backups and
   duplicates grow by them — accepted); `.bakes.nosync` is gone.
   Then S3b Undo, S4 memory manager (= (9)),
   S5 three layer pictures, S6 bake throughput, S7 rest, S8 stream, S9 device gate.
   **Owner rulings Nov 25 (design §7):** Q1 — stepping onto a never-drawn frame keeps the previous frame
   until the new one is whole (no soft-first). Q2 — a **Settings option "keep baked frames between launches",
   default OFF**; when on, the bakes are kept inside the scene's package, inside
   the disk limit; when off, as today (emptied at launch). Built in S2.
   Earlier text of this item, kept for its measurements: **Frame steps instant and unstaggered + bake speed** — scheduler stage 2, after (1). MEASURED with
   stage 3 (iPad 9 simulator, playcheck, end to end through a screen probe that reads to
   ~0.3 s): **one step to a whole settled frame 2.23–2.38 s**; **bake 0.19–1.52 s a frame** (six frames
   in 1.1–9.1 s — the frame on screen costs no walk; the spread is the bake waiting for memory behind
   the entering renders).
   Folded in (owner, Nov 21): **zooming out after zooming in on a 5000² canvas, the edges appear a
   moment late** — caused by `d72eb69f`'s window-sized pictures (only the visible window is drawn, so
   newly revealed edges wait for a redraw). Owner: minor, fix along the way. Likely shape: keep a small
   whole-canvas picture under the window so revealed edges show at once (soft) until the sharp redraw.
6. **Undo latency / raster Undo budget** — rides on stage 3's one budget (merged). Undo is
   the playcheck's peak phase: ~250 MiB transient outside the budget (not the vector walk's
   transparency layers). `UndoHistory`'s own 192 MiB cap is not yet an entry in the one budget.
7. **Re-check against `main`, then fix what remains:** stroke latency and pan hitches (open: live stamping
   `DabImageCache.stamp` on main, Core Animation converting every landed picture on main because
   `RasterSurface`'s byte order is not CA-native, the lift's `settleCelContent()` rendering one
   window-sized eraser picture on main), rapid-edit whole-iPad failures, Liquify shown while held,
   Move-exit gap, the red `SelectionEditUITests` swatch test.
   **Stroke-lift flicker (owner, Nov 26 on `ee72796b`: *"placing down a stroke still causes a brief flicker in the
   layer sometimes"*) — root-caused Nov 27, fixed, owner to confirm on the next build.** Two causes, both *ink drawn
   twice*, which only a translucent brush shows: (1) `retireUnlandedInk` left `heldInkView` up for ~340 ms after the
   base landed; (2) the flat row's under picture (`15327706`) put a copy of the frame under the transparent hosts
   after each lift — now **masked to the part of the canvas no host has drawn** (`maskUnderPicture`).
   `InkContinuityProbe` + `InkContinuityUITests` fail on both. The same rule covers erase (erased strokes
   reappearing briefly) and frame changes: the screen never shows a mix of old and new pictures — hold the last
   complete picture until every part of the new one is ready. Owner, Nov 25: check on the next build whether
   *"brief flickering when i lay down multiple brushstrokes"* still happens before any more work.
8. **Canvas freezes** — merged Nov 25 (`71f4fd6e`): one touch recognizer of our own replaces UIKit's pan /
   pinch / rotation / tap web (BUGS.md "The canvas stops answering two fingers"). On the iPad since
   `c15ad799`; owner to confirm with fast three-finger redos and palm-down pans in `Ships` and Test1 (a
   `flight-…` with trigger `canvas` is the report to pull; none is the answer wanted). Seven UI tests red on
   old main too, to triage under (7): Distort corner, two `FillLiveAdjust`, `GuideUITests` grid, wide-picture
   Move box, `MenuInterruption` toolbar gap, `testDenyOutsideSelection…`.
9. **One memory manager, not one per feature (owner, Nov 25: *"you decide … different features may have
   different specific memory management behaviors that they want programmed in … with some things needing
   to be strictly real time"*).** Decided: **go, designed together with stage 2 as one page** (time and memory
   are one admission question), reviewed before code. The page must settle:
   (a) *mechanism central, policy per feature* — a feature states facts (how it comes back: rebuild / disk /
   never; cost to get back; predicted next use; smaller stand-ins it accepts) and may supply hooks; the
   manager alone decides when; no feature frees or spills on its own;
   (b) *real time first* — R0/R1 run on reserved memory nothing else may take and never wait on disk;
   spilling and loading are R3 (R2 when predicted next), off main, stopped by a touch;
   (c) *arbitration* — one order (class, then cost-to-get-back per byte freed, then recency), a floor per
   feature so none starves, limits against thrash (minimum stay, no spill of what was just loaded), a job
   that holds memory never waits for more; (d) one disk limit, write rate bounded, spill only what is dearer
   to rebuild than to reload; (e) proof: the gate with a trace — zero R1 waits on disk, zero spill/load work
   on main, hit rates per feature; (f) **use every core** (owner, Nov 25): core counts read from the machine
   (the iPad 9's A13 is the minimum: 2 fast + 4 efficient cores and a GPU) — classes map to QoS (R0/R1 on
   the fast cores, bake / thumbnails / spill on the efficient ones), big jobs split into tiles across cores,
   how many at once set by cores *and* memory (today's bake allows 3), a core always left for the pencil,
   measured as throughput on the device's core count and not the Mac's. Start with layer pictures (~500 of
   888 MiB measured; unedited layers as two merged pictures); measure the stream before touching it.
   (g) **Close the uncounted ~300 MiB (MEASURED Nov 26):** at the undo peak the app sits ~296–304 MiB above
   what `MemoryBudget` holds, **on main too**; the gate's 277 MiB margin over the 888 budget only passes on
   slack. S4 makes that memory asked-for (an R1 reserve, R2 pictures R1 can evict) instead of re-ruling the
   0.48 fraction.
10. Audit follow-through, streaming on the real link, smaller asks below.
11. **Liquify lags and 100% only smudges (owner, Nov 26, on `ee72796b`).** *"liquify needs to be real time. It seems to
    lag alot. Also when power is set to 100% (default) it should be powerful enough to completely grab the original
    point under the pen, not just drag it like a smudge."* Liquify keeps up with the pen (SCHEDULER.md rules); at
    100% the pixel under the pen at touch-down stays under it for the whole drag (a grab, not a decaying push);
    lower power blends toward today's smudge. Also: *"liquify needs a visual indicator of how big the brush is when
    a stroke is being made. same circle thing as the eraser."* — reuse the eraser's size circle (same view) while
    a Liquify stroke is live. Owner order: **after the scheduler (S2–S9)**.
12. **Puppet warp — a Move mode (owner, Nov 26; Nov 27: *"make the queued puppet a move mode (like freeform or
    distort)"*).** A mode of the Move tool beside Freeform and Distort, acting on the selection (or the cel); not an
    Edit-menu icon. **Raster and vector** (raster pixels bend like Liquify; vector points move, staying crisp and
    editable); **pins: tap inside the selection to drop pins, drag one and the shape bends around it while the
    others stay put, tap a pin to remove it, commit with a button, one undo step.** No rotate handle. Reuse the
    ARAP solver (vector interpolation's lattice+ARAP) and Liquify's raster warp; build no second deformer. Owner
    order: **after the scheduler**, beside (11).

## Current — iPad build `ee72796b` installed 2026-11-26, owner check pending

- [ ] **November 16 iPad test (owner, Test1, 5000², 5 vector layers).** *A build this faulty must never reach
  the iPad; fix everything, audit the repo for spaghetti, keep going without stopping* — the audit looks for
  less-visible defects of the same kind. Shipped Nov 17, **owner to confirm:** Undo lag, the circle-and-line
  Fill (Mend Gaps with Reach sufficient must cover beneath the line while keeping the circle's outer
  boundary), rapid draw/Undo, orange bars on entering Test1. Owner also recalls Fill latency and a crash
  when rapidly filling several regions.
- [ ] **`SelectionEditUITests.testTheColourSwatchOpensThePickerOnTheLinesOwnColourAndTheLineFollowsItLive`
  red on an iPad 9 simulator:** `emptyToolbarPoint` finds no 44 pt gap in the portrait toolbar (the stale
  premise fixed in `GraphEditorFingerUITests` by launching landscape); same in `SelectionEditLiveUITests`' two
  picker tests. Also red on `main`: `SelectionAndMoveUITests.testDenyOutsideSelectionClipsStrokeUntilToggledOn`
  (Rectangle mode).
- [ ] **Fix the November 16 audit findings** ([docs/AUDIT-2026-11-16.md](docs/AUDIT-2026-11-16.md), 18
  ranked). Repeating defect: RAM-derived budgets (192 MiB on iPad 9) tested at 2048² that silently decline,
  scale down or drop history at 5000². Liquify's notice still says only "couldn't be prepared". **Open:** the
  canvas-size ceiling measures the app, not backboardd's 1,850 MiB; three bitmaps per vector cel; unbounded
  static caches; commit/un-suppress still invalidates `.everything`; `renderIsolated` on the main thread. Add
  a gated 5000²×5-layer fixture for every budget consumer (`DeviceStressUITests` is the device half).
- [ ] **Raster Undo at 5000² is one whole-cel step (190.7 MB) against the iPad 9's 192 MB budget**, so raster
  layers keep only the protected minimum of history. Price raster steps by dirty tiles, as vector steps
  already are (0.11 MB a stroke).
- [ ] **Fix severe Undo latency.** Owner: drawing is responsive on the latest Release, but Undo still has
  *"enormous latency"*. No new broad audit or testing/storage framework. Leads: settled Undo's clipped repair
  copies a full image (~95 MiB per 5000² bitmap; PERFORMANCE.md §11.11b); On Top stream surface work shared a
  serial queue with vector rendering (a separate stream worker is in the source — check it was the delay). On
  the iPad: one Undo per quiet interval, stream off vs a moving On Top stream, counting rasters and timing tap
  to ink disappearance; pair an Undo press with the accepted base picture in the recorder. Change the
  renderer only if that comparison supports it.

## Open reports and asks

- [ ] **Auto-resigner ("PaintApp is no longer available", ~10th time; owner Nov 20: *"Fix it well and fix it
  once"*).** Merged and live ([docs/RESIGN.md](docs/RESIGN.md)); the install stage now defers while the app
  runs. Open: confirm the first real expiry (Nov 28 03:31 UTC) renews unattended.
- [ ] **Crash catcher (owner, Nov 19).** Merged and installed: `UncleanExitWatch`, MetricKit diagnostics, the
  fading reopen notice, `tools/pull-ipad-crashes.sh` (pull only when the owner asks). Owner to confirm on the
  iPad (a force-quit is a background end and rightly reports nothing; a real backboardd Jetsam or Xcode's Stop
  while drawing is what raises it).
- [ ] **Intermittent whole-iPad failures during rapid edits.** Black screen and brief restart during draw →
  Undo → draw; a crash after repeated Fill (Nov 11); **rapid To Cross erasing on Test1 (4096²)** triggers it.
  Coincided with a running stream. Compare with and without a stream; check native stream-host rebuilds, Fill's
  full-size reference image (~95 MiB a pass with a stream in the reference) and preview-to-base handoff.
  Preserve exact Fill pixels; measure before naming a cause. Possibly the 1,850 MiB backboardd finding.
- [ ] **Show vector Liquify while the stroke is held.** Live-preview fix installed; **real-Pencil
  confirmation is open.**
- [ ] **Confirm the one-tap Move report in Test.** Lasso visible vector ink and tap Move once; the untouched
  box stays up; one Undo cancels the zero-nudge lift. Use a disposable copy for a drag or Set Down. Also
  verify older physical workflows on real scenes (clipboard menus, Mend All Fills, saving and recovery).
- [ ] **Move-exit gap.** Owner prefers the lifted drawing stays visible until the compositor's finished
  picture shows; stream displacement after release or Set Down. (Status unclear — check whether the shipped
  Set Down continuity covers it.)
- [ ] **Windows streaming on the real link** — see (27). The stream host's TCP accept can replace an active
  iPad, so probe only from the real desktop session with Kevin; avoid hosts that repeatedly prompt for
  firewall access; do not poll an unreachable host. Qualify bounded Windows discovery (DNS name limits) on
  the real host too.
- [ ] **Deferred: view previous crash reports in the app**, like recordings. Owner: *"at some point if it
  is possible."* Wait until requested.
- [ ] **Retire the inline legacy migrations** (compositor Input A/B slot ranking; pre-group-property
  marker) through the one-shot package repair, preserving Projects/Backups/Trash and order, then delete the
  decoder branches. (Status unclear — check.)
- [ ] **Bound stream timing storage between displayed pictures:** keep only count, total and max in the
  existing measurement owner, preserving cadence and log output. (Status unclear — check.)
- [ ] **Smaller audit findings from October 29 (status unclear — check each against `main`):** shape handles
  divide by a non-positive canvas scale during a tiny pinch (reuse the object overlay's guard); a placed
  picture saved at scale 2 reloads at scale 1; Release UI-test target should build only the active
  architecture; compiler-warning triage (259 occurrences — no blanket `nonisolated(unsafe)`, no scheduling
  changes without tracing callers).
- [ ] **Architecture audit follow-through (status unclear — check).** Owner, 2026-10-24: *"codebase
  cleanliness and good architecture as well as performance is a priority"*, *"Zombie code or bloat … should
  be dealt with. Dont be afraid to prune."* Findings in docs/ARCHITECTURE_AUDIT.md, most reported implemented;
  run whatever final-source gates were never run once on `main`. Mode3 (To Cross) final Release cost and the
  crash cause remain unmeasured.
- [ ] **macOS prompts for ChatGPT access to OneDrive / other app data** (cause unproved). Keep scope to the
  repository, PaintWork and owned-simulator paths; do not scan cloud folders or change privacy settings.
  (Status unclear — check.)

**Owner working rulings that outlive any item:** an owner report lands here before any worker starts; a
blocked release must not stop other open work; root causes, not workarounds; old files are repaired once by
a throwaway script and the decoder knows only the current format.

---

## (27) Stream the computer's screen as a layer

Built through stage 4 ([STREAM.md](docs/STREAM.md)). **Remaining is stage 5 on the real link, with the owner
at the laptop.** The brief (2026-09-13), as it still constrains: stream the Windows screen as a layer live
(Blender rotoscoping); a Windows-side drop box for images/videos and, if possible, iPad export back; one layer
holding the stream object; options bar with Freeze and Bake Frame (Bake splits the cel and replaces the stream
with an image of that frame); *low latency, must not lag the main thread*; movable with Move; *many screens or
one specific app*; a streamer that could one day merge into a Windows build of the app; the computer may be
turned off and on mid-session; *"stream layers actively moving do not have to be rendered."*

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

- [ ] **Audit for code specific to this iPad (very low priority, owner Nov 25).** Only as part of a Windows or
  Android version, if he ever decides on one. The standing rule (AGENTS.md) covers new and touched code.

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

Items are in queue order and leave **whole** when merged, not when a branch exists (owner, 2026-09-06:
*"Basically I want to be able to read the tasks on TODO clearly without already finished tasks."*). Write
what the artist sees or wants, the current lead, and the owner's own words where they constrain the fix;
receipts and gate counts belong in `git log` and HANDOFF.md. Check an existing item before adding one in
different words. Cite a symbol, not a line number. Three in flight at once unless the extras need no
simulator. Verify a status before trusting it, including this file's own. Do not re-add a finished item to
make a citation work.

**Old files are repaired once, never read forever** (owner, 2026-10-10: *"no legacy code … repaired by a
throwaway script the session makes"*): a format change ships a one-shot repair of Projects, Backups and Trash
at launch; the decoder knows only the current format; the repair is deleted once the owner confirms.

The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1 (the owner works at 2048×1024, though the
Nov 16 test scene is 5000²).
