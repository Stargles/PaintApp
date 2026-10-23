# Handoff

<!-- Current state and next step only. Detailed rationale belongs in specs, evidence and history. -->

**Start here:** read AGENTS.md, this file, CLAUDE.md, TODO.md, BUGS.md and the relevant specification.
Verify origin and every tmp branch. Active worktree: `~/PaintWork/PaintApp-s49-integration`, branch
`tmp/s49-integration`. Budget already permits useful agents; prioritize usage/quality over speed.

## Checkpoint — 2026-10-23

Main is `5e93bf0`; Liquify remains unmerged. The candidate app/runner have now been installed and
launched by the authorized physical tests. No final restored Release deployment has occurred.
Container Documents and the owner-supplied current external PaintApp ZIP are preserved and verified
under `~/PaintWork/s50-liquify/device-backup-2/`; the backup gate is satisfied. The September9
fallback Export index is not an authoritative inventory of the external library.

Simulator qualification is complete and source remains unchanged:
- Fast Debug and Release: each5,282 =5,278 passed+4 skipped, zero failures;256 classes.
- Full Release:5,864 =5,799 passed+3 failed+62 skipped;398 classes, exact census match. All three
  reds passed together unchanged serially3/3. Their parallel causes remain unproved. All eight
  Liquify UI workflows passed. Zero System Failures/restarts,753 source hashes unchanged.
- UI linters:85 SF Symbols,137 shared helpers, both clean. Every owned simulator/clone is deleted.
Evidence: `~/PaintWork/s50-liquify/{fast-3,full-release-closeout.txt,release-ui}/`.

Physical native sampler C benchmark **passed1/1, zero skips** on retry2. First invocation failed only
UI-automation initialization before any selected method; the owner then asked to retry and noted the
device sometimes prompts to enable automation. Retry2 measured native component cold428.577ms,
four warm17.177–18.066ms. All six PNGs reviewed; held/committed decoded bytes exactly agree. The
initial blank batch-image display was a presentation artifact, resolved by reopening the identical
PNG alone. This is component cost, not app gesture latency or a retention test. Evidence:
`~/PaintWork/s50-liquify/physical-benchmark-2/`.

Physical legacy attempt1 ended **5 total=1 passed/4 failed/0 skipped**. Playback passed. InkUnderTransform
and graph-node methods stopped at the temporary full-screen canvas-bounds premise. Move stopped at
its existing exposed-row premise (row0.6 versus dock top0.52654). Grey-pan setup could not hit the
size height field. These are unresolved physical test premises, not qualified feature assertions.
No Liquify invocation/retry followed. Native/DD ownership returned to root. Screenshot diagnosis is
confirmed: raw1620×2160 capture has EXIF orientation8 and displays2160×1620; AX canvas is
{{56,0},{1024,810}}. Both temporary crop and MidGestureSampler ignore orientation, so their pixel
coordinates are invalid. Prepare one orientation-aware full-screen image seam shared by both readers,
plus a visible Move row and floating-keyboard-safe64×4096 canvas setup. Architecture agent owns the
external temporary candidate only; root reviews before apply/build. No app-source edits, weakened
assertions, settings/library resets or preset changes. Playback passed unchanged; rerun affected four
rather than repeating it or the accepted benchmark. Review approved the shared UIImage.draw renderer
at original scale, exposed PopoverDismissRegion taps, and consistent rowAboveTheDock Move probes.
Grey's temporary paperRect oracle is independently invalid: it always returns a static square for a
64×4096 document, so cannot report pan. Replace that adapter-only geometry with the actual exposed
scale/rotation/offset applied to64×4096, preserving40pt/15pt movement and0.002 width assertions;
label those exposed geometry, and inspect the full screenshot. No app or committed test source changes.
Root reviewed the final grey delta and all eight original SHA guards and authorized guarded
`device-build-3` now. Architecture agent exclusively owns native/DD through clean/build-for-testing,
restoration and frozen seal/profile verification, then affected legacy4 (exclude passed playback)
and Liquify2 only if the previous gate passes. Expected4/2, zero skips; stop on any real failure.
Build3 clean/build/verification/restoration passed; all753 qualified hashes match, eight adapters
restored,114 frozen entries verified, compiled/frozen app+runner strict seals and five-day profiles
pass. Build2 and the accepted benchmark are untouched. Affected legacy attempt2 was cancelled with SIGINT scoped to owned PID12589 after confirming zero
selected Test Case starts: Xcode explicitly reported the iPad locked. Exit73/TEST EXECUTE INTERRUPTED;
xcresult1 synthetic "Testing was canceled" is not a selected feature failure. No attachments/scenes,
no Liquify/retry. Source753 hashes and all8 restorations exact; no owned process remains. Evidence:
`physical-legacy-2/{report.txt,final-status.json,source-checkpoint.json,cancellation.json}`.

After fresh owner unlock, physical-legacy-3 ended **4 total=2 passed/2 failed/0 skipped**, exit65.
Transformed raster stroke and graph-node drag passed unchanged; graph exposed36 updates over2 passes.
Move reached its actual held-pixel oracle and failed (old ink blank AND destination>50ink while held).
Grey stopped before pan at off-paper premise: finger+travel627pt is not<paperLeft561.6704. No Liquify
invocation/retry followed. Preserve these real outcomes, not green qualification. Native/DD is idle.
Two independent temporary-harness root causes are now evidenced (not app regressions):
- Grey mixes native portrait XCUICoordinate.screenPoint with displayed landscape AX/image coordinates.
  Here display(x,y) maps to native(810−y,x), explaining567+60=627. Use AX-frame interpolation only
  for the displayed surround premise; use publiccoordinate.screenPoint and coordinate.withOffset(60,30)
  .screenPoint for native path endpoints. The private synthesized event record must then use native
  orientation1 (matching all captured public records), not UIDevice landscapeLeft→3.
- Move's public drag correctly rotates withOffset. The added closeLayerRail toolbar tap explicitly
  commitsAllInteractiveState, ending Move. Before PNG confirms no box/bar; video shows no drawing
  surface toast. Replace only that temporary closure with existing layerOptions.close (callback clears
  layerOptionsID only), leaving right rail clear of existing probes; assert Move still exposed before drag.
Root reviewed those proposals; architecture agent prepares three minimal external hunks and guards for
review before any build. Keep all distances, gesture steps/stagger/duration, predicates/counts/deadlines
and40pt/15pt/.002 grey thresholds. No app-source, preset or settings changes; native/DD idle. No retry yet.
Build3 frozen xctestrun SHA: `125bd30baf4a3567a173fd9b4b6313ba83b661e6490898db94b386ca8ae28da9`.

## Next

1. Diagnose the two physical-legacy-3 failures from actual frames, coordinate spaces and held sample
   counts. Seek one shared adapter root cause. Preserve every assertion/threshold/deadline and the
   original fixture. Review and record any correction before rebuild/retry. Two passing legacy checks
   and the accepted benchmark need not be repeated if their production source remains unchanged.
2. After corrected physical legacy qualification, run the two safe unseeded Liquify Push workflows.
   Preserve full pictures and disposable-scene identities. Build3 frozen products are archived;
   hardware UDID `00008030-000151492EC3C02E`, devicectl ID
   `E3B83820-DF74-5042-B52B-0D5BA17E4877`.
3. Only after physical qualification, clean/build the restored Release with matching arguments,
   strict seal and current five-day profile verification; install and launch normally. Keep one-shot
   repairs until the owner confirms real scenes. Prior-writer/fault evidence already exists under
   `~/PaintWork/evidence/s49-liquify-material-{format,model}/`.
4. Update physical PERFORMANCE evidence; remove TODO(178) whole and completed freeze-log request
   in the qualified merge. SESSION_LOG keeps five entries. Fetch/recheck TODO/HANDOFF, ff-merge
   through the absolute main worktree path, verify SHA, push and clean up owned task artifacts.

## Evidence and decisions to preserve

Ownership cleanup `c78aac8` removes the sole-consumer generic presenter wrapper; existing live-edit,
synchronization and cancellation remain. Spatial material rendering uses VectorCanvas with tile-scoped
work. Reuse prior material/storage/refusal/model fault proof in `~/PaintWork/s49-liquify-logs/`.
Two malformed identity fixtures (`621c15d`, `b244a46`) retain all original assertions and have focused
baseline/fault/restoration proof. The unasserted mid-rotation raster photo tail was removed (`0cabd6c`).

Quiet Release producer gate 2/2: eight exact pictures and 18 frozen inverse fixtures match. Retain
batching: hard/pattern medians 0.173/1.868s, 19.1%/23.3% of scalar cost. Patterned worst case remains
seconds on the simulator; physical C first-use cost remains open. See PERFORMANCE and
`~/PaintWork/s50-liquify/producer-release-1/`. The earlier Debug linked workflow really missed its 15s
deadline; Release qualification does not relabel it green. Diagnosis: `linked-ui-diagnosis.md` beside it.

Freeze-log read is complete: six October16–18 repairs correlate to Releasef813346/app840d68a, before
Liquify. 346 sequences include 340 controls and six repair hits, not six proven visible freezes. New
Pencil/cancel cases disprove a universal late-third fix; no common cause or behavior change. BUGS.md
and `~/PaintWork/s50-freeze-logs/` hold findings. The owner confirmed on 2026-10-23: "I only noticed the repair message." No visible freeze reported for that period.

Other TODO: laptop streaming(27) owner-deferred; multiple cels(22)/linear light(10) deprioritised;
importers(37) dropped. Audio(28), video editor(30) and interpolation overhaul await owner briefs; no
research now. (179) is complete, including six physical probes in PERFORMANCE §30.7.
