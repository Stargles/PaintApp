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
No Liquify invocation/retry followed. Native/DD ownership returned to root; architecture agent is
preserving evidence and diagnosing layout/coordinate assumptions read-only. Do not weaken tests,
reset libraries/settings or change presets to get green.

## Next

1. Diagnose the four physical premise failures from actual screenshots and hierarchy. Record and
   review any minimal test-adapter correction before rebuilding; retain all feature assertions,
   gestures, counts and deadlines. The original frozen device-build-2 products remain preserved,
   with every temporary source restored and753 qualified hashes unchanged.
2. Rerun only affected legacy checks with corrected physical premises, then the two safe unseeded
   vector/raster Liquify Push workflows. Preserve full pictures and disposable-scene identities.
   Do not repeat the accepted cold sampler measurement. Hardware UDID
   `00008030-000151492EC3C02E`; devicectl ID `E3B83820-DF74-5042-B52B-0D5BA17E4877`.
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
