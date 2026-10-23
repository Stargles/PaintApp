# Handoff

<!-- Current state and next step only. Detailed rationale belongs in specs, evidence and history. -->

**Start here:** read AGENTS.md, this file, CLAUDE.md, TODO.md, BUGS.md and the relevant specification.
Verify origin and every tmp branch. Budget permits useful agents; prioritize usage/quality over speed.

## Checkpoint — 2026-10-23

Liquify is complete and qualified for this integration merge. Final normal Release build `cbd297e`
uses the unchanged qualified production source (last ownership cleanup `c78aac8`). Clean/build0,
all753 source hashes exact, strict deep seal verified, profile expires2026-10-30T00:18:54Z
(October29 evening Toronto), over five days at install. Installed `Starg.PaintSoftware` and launched
normally with **no test arguments**, PID52717 observed alive. Preserved app and install/launch/signing
records: `~/PaintWork/s50-liquify/final-release/`. No uninstall, settings/library reset or preset edits.

**Owner confirmation received,2026-10-23:** existing artwork "looks right". The one-shot file
repairs may now be retired per AGENTS.md. Active cleanup tree:
`~/PaintWork/PaintApp-s51-cleanup`, branch `tmp/s51-cleanup`, from maina17e69b. Remove repair-only
code/tests/wiring while retaining current validation and update backups; no canvas recognizer or
project-location migration removal. TODO records the scope before work.

**Gallery cleanup complete:** owner manually deleted all test scenes and confirmed completion.
No further deletion is authorized or needed. Future physical checks must track unique owned scenes
and clean those through existing Trash, verifying fresh inventory before closeout.

Repair retirement commits `b0917a2`/`cf37eab` remove six services and converter-only tests/wiring;
strict current manifest/material/recipe/stream restore refusal remains. Exporter fixes `e2d86098`/
`4e3f0e16` preserve relative folders and refuse overwriting their source; PBX test membership fix
`d9dab5bb` makes the actual four new logic tests available in the UI-test target. Current census:
fast **5,251 /254classes**, full **5,833** (three private static testBrush factories are not tests).
Focused retirement tests117/117 and latest stream/storage25/25 pass; four faults red then restored.
Exporter actual-source Mac XCTest4/4 baseline/restored and five faults red; final native tiers pending.

**Device library copied and checked:**256packages =10Projects+228Backups+18Trash,3,180package files,
567,855,190B; every package path and byte count matches index, no failed copy. A second device index
has identical paths/titles/sizes. Temporary568MB app-container export was cleared through index-only
launch; app reopened normally. Evidence: `~/PaintWork/s51-cleanup/current-library/`. The installed
intermediate audit app is old-repair-source788f576 plus exporter safety fixes, not the final retirement
build. Its strict signature/profile pass; expiry remains2026-10-30T00:18:54Z.

**Current-library audit passed1/1:**256packages,2,181cels,95,350strokes,93streams; zero decode
failures or pending repair findings. Copied-input hashes unchanged, temporary source removed exactly.
Full723tracked source/PBX files frozen. Native ownership is with retire_file_repairs for final
Release fast tier plus recovery/key UI3. Final Debug is green:5,251 total=5,247passed+4skipped,
zero failures; exact254class/static census. Release is running with the same frozen source. Own simulator1951527B-3A28-46D8-9FDA-E970663EE733, simlock, serial. Root owns docs and final
merge/normal Release install after all gates. No physical UI fixture creation/deletion remains.
Audit findings, if any, must be resolved before deleting repair services from the installed app.

## Qualification to reuse

- Fast Debug and Release: each5,282 total=5,278 passed+4 skipped, zero failures;256 selected classes.
  `~/PaintWork/s50-liquify/fast-3/`. Source unchanged after source head `2b330c9`.
- Full Release:5,864 total=5,799 passed+3 failed+62 skipped;398 classes, exact static census.
  All three reds passed together unchanged serially3/3. Exact parallel causes remain unproved;
  no product/test fix. Four actual workers, zero System Failures/restarts. All eight Liquify UI
  workflows passed. `full-release-closeout.txt` indexes source hashes, stills and counts.
- Physical: native sampler1/1 (`physical-benchmark-2`); five distinct legacy workflows all pass:
  playback (`physical-legacy-1`), raster-under-transform and graph (`physical-legacy-3`), grey pan
  (`physical-legacy-4`), Move (`physical-legacy-5`). Graph36 updates/2passes, Move37/4; Move held,
  settled and oneUndo assertions unchanged. Liquify2/2 (`physical-liquify-1`): vector/raster under
  finger, oneUndo, raster Redo/save/cold-reopen. All full pictures reviewed at native iPad9 size.
- UI identifier/helper checks clean:85 SF Symbols/137 helpers; PBX plutil clean, prior1334-ID census
  has no duplicates. All owned simulators/clones deleted. Full Debug UI was not run; the earlier
  linked Debug15s miss remains real, separately diagnosed in `linked-ui-diagnosis.md`.

Historical physical failures are **not** relabelled green. Corrected temporary harness premises:
EXIF8 screen orientation, visible Move row, native/displayed grey coordinates and event orientation,
and an unnecessary dismissal that ended Move or addressed an already-closed card. No feature
predicate, threshold, gesture timing or deadline weakened. Builds2–5 froze114 entries each, restored
all8 temporary test files byte-exact, verified753 source hashes and strict app/runner seals/profiles.
Canceled/locked initialization attempts never entered a selected method. Every raw result remains
under `~/PaintWork/s50-liquify/`; no native jobs remain active.

## Architecture, cost and protected data

The sole-consumer generic presenter/proxies were removed; `LiquifyProcedure` owns its snapshot and
uses existing live-edit synchronization/cancellation. Spatial material work stays tile-scoped through
VectorCanvas, with no whole-scene cache. Quiet Release producer2/2:8 exact pictures and18 inverse
fixtures match; hard/pattern medians19.1%/23.3% of scalar reference. Worst pattern still takes seconds
on the simulator. Invalid identity fixtures retain all original assertions and baseline/fault proof.
PERFORMANCE records the qualified native physical adapter: cold428.577ms, warm17.177–18.066ms for
448² output; exact six pictures, one-tile peak sampler charge9,050,880B. These are component costs,
not app gesture latency or retention evidence; use the prior dedicated100-draw retention gate.

Backup gate is satisfied: container Documents134 files/19,662,670 bytes hashed, plus the owner's
current external PaintApp folder ZIP327,981,935B, all3,830 members CRC/SHA/safe-path checked and
source/copy SHA equal. Actual ZIP has18 Projects+99 Backup manifests, empty Trash. It is preserved
at `device-backup-2/external-library/`; source Downloads/PaintApp.zip is untouched. The September9
fallback Export index is not a current external inventory. Tailscale reaches iPad but no file service
is enabled; Apple developer transfer cannot read that File Provider root. Do not re-block on that
old comparison. Scratch titles include Untitled and `Raster 06F7E064`; exact external package IDs were
not exposed, so no broad cleanup/deletion was attempted. Container brushes/palettes stayed hash-identical.

Freeze-log read is complete in BUGS and `~/PaintWork/s50-freeze-logs/`: six October16–18 repair flights
correlate to Releasef813346/app840d68a, before Liquify;346 deduplicated sequences340 controls/6 repair
hits are not a failure rate. Owner saw only the repair message, not a visible freeze. Keep the repair;
no speculative UIKit behavior change. The completed log-read request leaves TODO with this merge.

Other TODO is explicitly deferred: laptop streaming27; multiple cels22 and linear light10 deprioritised;
brush importers37 dropped; audio28, video30 and interpolation overhaul await briefs. No research now.
