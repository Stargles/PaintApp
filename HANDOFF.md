# Handoff


## Current checkpoint — 2026-11-12

Kevin resumed on November 12. Priority is the whole-iPad black screen during rapid drawing/Undo or repeated Fill
while a stream is running, plus severe Undo latency. TODO.md holds the reports and recording paths.

- November 12, 18:59 Toronto: owner checked whether work had stopped. The profile still
  expires at 02:06:03 on November 13. Independent settled Undo review found a known full-image
  copy (about 95 MiB at 5000²) even for a clipped repair, not an extra render. The existing
  measurements do not identify it as the reported delay. `UndoRepairBench` tracks clipped work
  without a stream or screen timing. Use matched Action Recorder and screen footage for the
  physical comparison in TODO. No change to the qualified release.

- November 12, 19:10 Toronto: Kevin reiterated to keep working through the queue.
  The exact candidate stays pinned. Verified already present in that build: dead Fill field
  and all three writes gone (`c80a545e`); image Redo preserves order and source identity
  (`2fc0fc10`); seven split callers refuse atomically and refused crop preserves actual gesture
  history (`a95a699a`). Exact Debug and Release covered all four. Repeated Fill/clip/stream
  UI also passed on unchanged Fill source at `cee6a049`. Removed these completed audit entries.
  Fresh freeze inventory matches the old one; comparison details are in TODO. Loop endpoint
  is fixed (`3a38bcd6`): both fast tiers and 4/4 cold UI passed. Old behavior failed the
  expected endpoint and recording/transport stop assertions while ordinary looping passed.
  Source restored and simulator deleted. See `crash-20261111/loop-recording-endpoint/` for
  results and inspected slider and Move screenshots. A distinct late-control hypothesis is
  in TODO. Keyed resize has a confirmed coordinate-space gap and its own branch. A read-only
  crash inventory refresh returned no new relevant reports.

- Owner asked at 19:14 why the connected iPad did not have the done build. Current device
  readiness was confirmed. Exact `6c0b37e6` device Release built and passed strict signature
  verification at 19:18. Artifact is `~/PaintWork/crash-20261111/device-qualified-Release/Build/Products/Release-iphoneos/PaintSoftware.app`
  (executable UUID `A186AF1F-08F4-3E20-93FF-DD6A84416C39`). Apple reused the profile expiring
  02:06:03 Toronto November 13, under seven hours from the check. The five-day gate stopped
  installation. Owner was asked about a one-time exception while other work continues. The
  manual expiry example now uses UTC, matching the renewer. It was verified across four
  timezones and both sides of the five-day cutoff.
  The installed line already includes the older features named in TODO. A separate branch
  owns the missing fresh-stream-frame-after-Set-Down check.

- Follow-through: the fresh post-Set-Down frame stayed at the committed placement in both
  stream modes (2/2 cold simulator tests at `3ed772aa`). Inspected owner-size images in
  `~/PaintWork/stream-set-down-frame/focused-look/` show matching blue/red rectangle bounds.
  The deliberate wrong-pose witness is running; whole class remains queued. Keyed resize
  candidate `5f3fbefd` passed three Debug logic tests and one cold owner-size pixel test.
  Visible positions and bounds matched before and after scaling; Undo/Redo/reopen passed.
  Artifacts are in `~/PaintWork/keyed-canvas-resize-evidence/`. Its deliberate fault and full
  gate still remain. Late scalar recording and exact clipboard cold checks are queued in TODO.
  Canonical reconciliation: the local main line's 52 pre-reconciliation commits touch only
  AGENTS, CLAUDE, TODO and HANDOFF. The exact tested source contains 629 commits after the
  common remote ancestor, including 606 already in installed d4. Reconcile those records onto
  an isolated qualified source line and assess the resulting history before any shared merge;
  preserve existing main and remote refs in the meantime.

- Latest verified code `6c0b37e6` is in `~/PaintWork/PaintApp-vector-liquify-live` and
  canonical local branch `tmp/qualified-live-liquify-20261112`. It adds continuous vector Liquify,
  a fence on canceled In Place previews, unique recorder filenames and the separate watchdog
  deadline fix. Vector/raster Liquify logic and UI passed **100/100** before the surface fence;
  the exact combined candidate passed **43/43** focused checks including streamed Liquify.
  Starvation and stale surface faults reproduced the intended failures and were restored.
  Root inspected held and Undo pictures in `liquify-live-look/`. The exact Debug and Release
  fast tiers each passed **5612**, with 0 failures and 4 opt-in skips out of **5616**.
  Owned simulator `4725E0DC-18B8-4985-960E-B55E530B6D80` deleted. Keep this source pinned.
  Next release: build signed Release from this exact worktree once Apple can mint a new profile.
  Last checked at 18:55 Toronto Nov 12. Current profile expires 02:06:03 Nov 13. No device build
  for this SHA, no install, and no change to renewal state. Earlier `cee6a049` device artifact
  verified but has the expiring profile. Check saved/unlocked readiness for installation.
- Retrieved five size-verified canvas flights with six distinct repairs from installed d4.
  Evidence and hashes: `~/PaintWork/crash-20261111/freeze-flights/comparison.md`. Nov 11 recorded
  a new gesture whose touches lacked all navigation and ink recognizers before they reset during
  that same gesture. Four late-third taps correlate with repair, but a healthy late-third tap
  disproves sufficiency. A Nov 8 check ran ~20 ms after a newer lift because the older callback
  stayed armed. That is a separate watchdog sequencing defect, not the navigation root cause.
  Replay the late-third touch batches with existing XCUITest synthesis on an owned simulator.
  `tmp/freeze-touch-sequence-20261112` from `cee6a049` is isolated. Treat green old-code replay
  as continuity only and avoid an unproven change to gesture admission. The owner reiterated
  that a timer fix is not closure. Prove the input path works without replacement, then delete
  the superseded recovery path cleanly once unnecessary.
  `freeze_replay` owns the temporary baseline witness and `freeze_watchdog_sequence` owns the
  proven timing bug, both isolated from the exact qualified device build. Recorder filename
  commits `0057a848` and `da6169eb` were imported as `32a245b1` and `3859d255` on the replay
  branch. Recorder logic/UI passed 22/22 in `freeze-baseline-replay`. Temporary replay `17ad7ff9`
  failed both visible fixture assumptions. Simulator compressed the intended 90 ms gap and
  introduced tap movement/pinch. Both follow-up pans bound and moved 84 pt, with zero repairs.
  Do not interpret the fixture failures as reproducing the iPad freeze or merge that test.
  `b53c54ad` fixes the separate stale deadline, passed standalone 3/3 and six deliberate faults,
  and is integrated in the diagnostic lane as `37260c6e`. Touch settle and recorder logic passed on the owned iPad 9 simulator.
  Physical input evidence with corroborating touch bindings is required for the reset root cause.
  Owner reports the iPad is on and available for tests, and the freeze is intermittent and notoriously
  hard to reproduce. Capture ordinary use where practical. A short clean run cannot prove resolution.
  No change to the exact qualified device build. See current owner-facing queue in TODO.
- The crash recording is Test1 at 5000 × 5000 and ends without a stop at 22:16:08 Toronto on Nov 7.
  Matching `~/PaintWork/crash-20261111/JetsamEvent-2026-11-07-221608.ips` kills `backboardd` at its
  process limit, about 1859 MiB. PaintSoftware held about 967 MiB and `videocodecd` about 20 MiB.
  Five nearby terminations restarted the interface while the OS stayed up. The exact installed
  executable UUID is `7639BBB7-8740-3CA1-A138-313C09A203B5`, Release `d4d59f6b` in `~/PaintApp`.
  This establishes the failure mode. It does not identify the memory allocation owner or verify
  the later Fill incident. Keep the reports and recordings; no scene/device mutation was made.
- The recording's Undo handler took 6.58 ms. Background vector rasterizations took up to 1.11 s.
  Undo patch `722b8ee3` (`08bedb8c` in integration) reuses the exact pre-append picture when a
  stroke is undone before the new render lands. Independent source review accepted the invariants.
  Debug `UndoRepairLogicTests` plus `UnlandedInkUITests` passed **47/47**. Root inspected the
  landscape screenshot in `~/PaintWork/crash-20261111/undo-look/`: second stroke gone and first
  retained. The two deliberate faults reached and failed the intended assertions (2/2 and 1/1);
  source was restored. Settled Undo’s full-image copy remains a separate cost to measure.
- Stream patch `d0c9eeb0` (`ac74b97e` in integration) closes the On Top refresh bypass only
  when the current stream window is shown. No In Place change. Combined Debug passed **81/81**
  including real H.264 stream colors across layer changes with zero extra native rasterizations,
  and rapid Undo pixels. Root inspected both owner-size screenshots in `crash-20261111/stream-look/`
  and `undo-look/`. Stream faults red as intended: 2/2 for base reuse (3 extra rasterizations in
  the UI) and 4/4 for coverage/landing. Clean source restored.
- Mend Gaps: exact freehand circle + short 6 px line on another vector layer, 12 px Reach and
  zero Edge Overlap, passed 1/1 at `a883be6b`. Root inspected Off and committed target-only
  pictures in `~/PaintWork/crash-20261111/mend-look/`. New possible failure for a densely sampled
  snapped circle: a conservative quadratic work charge can discard the support for all strokes.
  Baseline `2d5dfb96` reached the intended ON short-line pixel assertion and failed 1/1, with
  the surrounding and exterior premises passing. Fix commits `c2be8d2b` and `f6586212` on
  `tmp/mend-work-budget` are ready to integrate. They conservatively bound actual adjacent-neighbour
  scans, including stationary runs, and retain 64M work and existing bytes/pixel guards. No brush
  output or mending rules change. The exact shape and settings on the iPad are unknown.
  Integrated Mend source `2c26812a` passed both focused tests (2/2), including the formerly red
  long circle. The source-only branch commits are `c2be8d2b` and `f6586212`.
- Both touched stream/Undo UI classes and compatibility checks passed **17/17**, including playback,
  surround pan, Move/release and a stroke on a streamed canvas. November 12 running Debug also
  passed **5/5** Mend UI and **1/1** Graph drag through the actual gesture class, with zero failures.
- All **31/31** Mend logic tests passed on clean `2c26812a`. The deliberate work-bound
  fault failed its intended assertion and was restored.
  Both UI policy checkers passed. Exact Debug completed 5607 passed, 2 failed, 4 skipped out of
  5613, matching static selection. Only two Undo pricing assertions failed (MoveToNewLayer and
  PoseBake). The clipboard extraction `341d45d1`, already in d4, dropped Duplicate's unchanged
  source from pricing. Release did not start. Integrated `cee6a049` now includes cost repair,
  Fill surface reuse, and a test-only UInt8 literal correction after the first compile refused it.
  Exact `cee6a049` passed **79/79** in `resume-followup-focused-v2`, including both formerly
  red pricing suites, editable vector clipboard, Fill window/owner logic, and three cold Fill UI
  checks. Root inspected the selection, successive fills and In Place opacity attachments.
  Three Fill handoff fault builds failed their intended assertions and were restored clean.
  Exact `cee6a049` Debug passed **5610**, failed **0**, skipped **4** opt-in benchmarks out of
  **5614** (5608 static fast plus 6 UI). Exact Release passed **5604**, failed **0**, skipped the
  same **4** opt-in benchmarks out of **5608**. Both results reconcile with static counts. The
  owned simulator was deleted after verification. Exact code is also retained in the canonical
  repo as `tmp/qualified-rapid-edit-20261112`. Leave canonical main unchanged: it is not on the
  candidate ancestry, and fast-forwarding it would also promote 606 earlier audit/clipboard
  commits from the currently installed line without their separate qualification and merge.
  Device Release for `cee6a049` built clean and passed strict signature verification. Artifact
  `~/PaintWork/crash-20261111/device-Release/Build/Products/Release-iphoneos/PaintSoftware.app`,
  UUID `6FB924AE-6BFC-346B-95DC-8916DEF16946`. Apple reused the profile expiring Nov 13 at 02:06:03
  Toronto. Do not install with that profile. The existing install and renewer state are untouched.
  Rebuild with the fresh profile once available, verify again, and get fresh saved/unlocked iPad
  readiness. November 12 17:36 lock-state check reached the iPad and showed it locked.
- November 12 read-only preflight: iPad reachable but locked. Stable d4 artifact verifies and
  its signing profile expires Nov 13 at 02:06:03 Toronto. Check for a renewed profile before
  install; the current profile is below the five-day requirement. Fresh device readiness is
  needed for a saved-scene-preserving install and physical gesture checks. A later lock-state
  request could not establish its connection. Comparable stress uses a disposable 5000² scene,
  Apple Pencil rapid drawing/Undo and repeated Fill with the stream off and visibly running On Top.
  For settled Undo measure tap to ink disappearance after the base has landed in both conditions.
- Code worktrees `tmp/undo-before-land`, `tmp/stream-base-refresh`, and
  `tmp/rapid-edit-integration-20261111` are in `~/PaintApp`'s Git repository. Installed source
  `d4d59f6b` includes the prior audit and media import changes. Desktop main is older and must not
  be built as a substitute. The previous integration `cee6a049` is superseded by the pinned
  device candidate above. Canonical Desktop main holds records only.
- Fill investigation is source-only: native stream references may flatten a full canvas for a
  small fill window. A separate commit path uploads a preview image even when the fill's existing
  IOSurface already shows the exact render. In Place stream ticks reuse a surface pair while the
  window dimensions stay stable. Keep these findings distinct from the confirmed device report.
  Fill handoff `72fa2455` is integrated at `cee6a049`. It reuses the exact presented front on
  eligible vector Fill commits and keeps the prepared bitmap fallback for pending, failed, or
  mismatched previews. The preflight bitmap is still constructed. This avoids a duplicate display
  upload when eligible; there is no measured physical memory reduction yet.
  The crash-report viewer and interpolation overhaul stay deferred.
- Windows November 12: laptop answered SSH, configured key rejected. Desktop Commander
  lists the same laptop offline. No remote changes or tests. Real Blender/source/clipboard/link
  validation is in TODO and needs the actual Windows session.

## Resume rules

- Read AGENTS.md, CLAUDE.md, and TODO.md in order. TODO.md holds every outstanding task and ruling.
  Keep this file current before handing off. Older checkpoints remain in Git history.
- Delegate investigation, implementation and focused verification to fresh agents with short
  briefs. Root owns priorities, acceptance, the shared native lane and release decisions. Send
  active agents only relevant updates. Use one native lane and bounded disposable PaintWork output.
- Focus the reported crash and Undo workflow before broader audit items. Do not claim device
  resolution until the comparable stream/edit workflow is checked on the iPad. The read-only
  diagnostics are in `~/PaintWork/crash-20261111/correlation.md`. Do not use old deleted PaintWork
  paths as runnable evidence. Keep the existing signed app and renewer state until a verified install.
