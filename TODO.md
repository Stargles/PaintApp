# TODO

The owner's asks, live. Recorded when they arrive, deleted whole when done **and merged**.
[BUGS.md](BUGS.md) is for what *we* find; [HANDOFF.md](HANDOFF.md) is the checkpoint, never the only
record of an outstanding task. Items marked "(status unclear — check)" were carried from older notes and
could not be verified as open or closed; verify against `main` and `git log`, then delete or fix.

## Current — iPad build `9792e799` installed 2026-11-17, owner re-test pending

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
- [ ] **Fix the November 16 audit findings** ([docs/AUDIT-2026-11-16.md](docs/AUDIT-2026-11-16.md), 18
  ranked). Repeating defect: RAM-derived budgets (192 MiB on iPad 9) tested at 2048² that silently
  decline, scale down or drop history at the owner's 5000². Silent refusals: done Nov 17 — artist-facing ones
  already noticed except warp/posed raster (Move, warp, posed bake), which now say "Not enough memory
  to do that"; Liquify's notice still says only "couldn't be prepared". **Open:** the canvas-size ceiling measures the app, not
  backboardd's 1,850 MiB; `CALayer.contents` installs outside the paced path; raster thumbnails at canvas
  size; three bitmaps per vector cel; unbounded static caches; commit/un-suppress still invalidates
  `.everything`; `renderIsolated` on the main thread. Add a gated 5000²×5-layer fixture for every budget
  consumer (`DeviceStressUITests` is the device half).
- [ ] **`MoveBoxPrecisionUITests.testAFingerPressedBesideAVectorBoxDragMakesItAFifthAsFarAndLeavesTheCanvasAlone`
  fails at its XCTUnwrap (line 54)** on an iPad 9 simulator. Triage stale vs real.
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
