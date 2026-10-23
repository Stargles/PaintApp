# Handoff

<!-- Current state and next step only. Detailed rationale belongs in specs, evidence and history. -->

**Start here:** read AGENTS.md, this file, CLAUDE.md, TODO.md, BUGS.md and the relevant specification.
Verify origin and every tmp branch. Active worktree: `~/PaintWork/PaintApp-s49-integration`, branch
`tmp/s49-integration`. Budget already permits useful agents; prioritize usage/quality over speed.

## Checkpoint — 2026-10-23

Main is `5e93bf0`. The iPad still runs recovered Release `17b438c` (app source `840d68a`); the owner
confirmed it opens. Its verified profile expires 2026-10-30. The renewal repair aligns clean/build
arguments, fails closed on clean errors, verifies signatures and requires five days of profile life.
Nine isolated scenarios and four mutations passed. See `docs/bug-evidence/auto-resign-2026-10-22.md`.

**Liquify is unmerged and uninstalled. Simulator qualification is complete; physical work is blocked
on device availability.** No native jobs or agents remain active; every owned qualification simulator
and clone is deleted. All eight temporary physical test adapters are restored byte-exact; all 753
qualified app/test/project hashes match. Later commits after fast source `2b330c9` are docs only.

- Fast Debug and Release: each 5,282 total = 5,278 passed + 4 skipped, zero failures; 256 selectors.
  Evidence: `~/PaintWork/s50-liquify/fast-3/`.
- Full Release: 5,864 total = 5,799 passed + 3 failed + 62 skipped; 398 classes, exact census match.
  All three reds passed together unchanged serially: 3/3, zero skips. Two concern StreamLiveEngaged;
  one concerns LayerPanelControls mover visibility. Exact parallel causes remain unproved; no fix.
  Four actual workers, zero System Failures/restarts, unchanged source hashes. Command wall 4,751s;
  summed class time 17,970.666s. See `~/PaintWork/s50-liquify/full-release-closeout.txt` and its indexes.
- All eight Liquify UI workflows passed in the full run (vector/linked 3, raster 5). Root inspected
  reshape/Undo/reopen/source-follow images and settled controls at native iPad9 landscape size.
  Earlier isolated evidence and hashed Documents copies: `~/PaintWork/s50-liquify/release-ui/`.
- Final UI linters pass: 85 SF Symbols, 137 shared helpers. No assertion, gesture or deadline weakened.

Physical staging attempt `device-build-1/` stopped at **clean exit 70**, before compilation. Xcode
could not prepare the named iPad and requested an unlocked device on the same LAN or attached by
cable. Keychain unlock succeeded; build-for-testing was never invoked. No products/signature checks,
install, launch, tests or device-data access occurred. All sources restored and native ownership
returned to root. Report: `~/PaintWork/s50-liquify/device-build-1/report.txt`.

A required saved/unlocked readiness question is pending with the owner. Earlier passive preferences
retrieval also timed out; no backup coverage is confirmed. Do not blindly retry. Hardware UDID:
`00008030-000151492EC3C02E`; devicectl ID: `E3B83820-DF74-5042-B52B-0D5BA17E4877`.

## Resume after the owner makes the iPad available

1. Refresh actual availability. Establish library location via the copied preferences key
   `PaintApp.projectLocation.bookmark`; back up/hash all container Documents and any external
   Projects/Backups/Trash before install/launch. An external root may need owner help; never assume
   Documents covers it. Never reset libraries/settings, edit presets or choose a storage invitation.
2. In a **fresh evidence directory**, stage the guarded five-file legacy patch, reviewed two-file
   Liquify patch and separately backed-up sampler benchmark. Reuse instructions/manifests in
   `~/PaintWork/s50-liquify/device-preparation/README.md` and
   `~/PaintWork/s49-liquify-logs/combined/final/`. Attempt1 preserves exact backups, candidate files,
   scripts, complete diff and failure evidence. Do not reuse its backup directories blindly.
3. One named-device Release build-for-testing, identical clean/build common arguments, fail-closed
   clean; verify app/runner signatures and five-day profile life. Freeze product/xctestrun provenance,
   restore all eight sources byte-exact and verify the 753 hashes. No broad suite with adapters active.
4. Run the native cold/warm sampler benchmark FIRST and ALONE, then five legacy drives and two
   unseeded Liquify Push drives separately: expected 1/5/2, zero skips. Inspect six native PNGs and
   full UI screenshots; preserve disposable-scene identities. Native component cost is not app gesture
   latency; the fifth legacy drive separately checks actual transformed raster drawing.
5. Final restored Release: matching clean/build arguments, verify seal/profile again, install and
   launch normally. Keep one-shot repairs until the owner confirms real scenes. The new executable
   repair signature converts older preupdate snapshots; its own newest snapshot is intentionally
   untouched. Prior-writer evidence: `~/PaintWork/evidence/s49-liquify-material-{format,model}/`.
6. Only after physical qualification, remove TODO(178) whole and the completed freeze-log-read entry,
   update SESSION_LOG (last five), recheck TODO/HANDOFF, ff-merge via the absolute main worktree path,
   verify SHA, push and clean up the task worktree. No unqualified Liquify deployment.

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
and `~/PaintWork/s50-freeze-logs/` hold findings. The optional visible-freeze question is not blocking.

Other TODO: laptop streaming(27) owner-deferred; multiple cels(22)/linear light(10) deprioritised;
importers(37) dropped. Audio(28), video editor(30) and interpolation overhaul await owner briefs; no
research now. (179) is complete, including six physical probes in PERFORMANCE §30.7.
