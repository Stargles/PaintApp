# Saved-file repair retirement — 2026-10-23

The owner confirmed existing artwork “looks right”, then manually deleted all gallery test scenes.
This satisfies the one-shot repair retirement rule. No automated gallery deletion was performed.

## Change

Removed `LegacyPoseTrackRepair`, `LegacyToolSettingsRepair`, `LegacyMaskRepair`,
`LegacyStreamPlacementRepair`, `LegacyLiquifyRepair` and `LibraryRepair`, including startup/restore
conversion wiring, retired preferences, converter-only tests, fixtures and PBX references.
Current strict decoding, update snapshots, staged restore safety, file/recipe/material/stream checks,
canvas recognizer repair and project-location migration remain. Current malformed-stream rejection
formerly hidden inside the converter now lives in `ProjectRecipeMetadata.validateRestoreStreams`.

The existing read-only `ProjectExport` flattened same-named packages from different folders, silently
replacing exported copies. `copyPackage` now preserves library-relative paths and refuses copying a
package into itself or over its source. Four new logic tests cover collision and source preservation;
its source is also explicitly compiled into the logic-test target. No product cleanup hook was added.
`CLAUDE.md` now requires physical harnesses to own uniquely identified fixtures, Trash only those in
teardown/finally, preserve owner settings/libraries and verify fresh inventory before closeout.

## Current-device library gate

The intermediate audit Release retained all outgoing repair code and contained the export fix.
Its clean/build shared arguments, strict deep signature and profile life were checked before install.
Its profile expires 2026-10-30T00:18:54Z. The preserved historical AirDrop archive was not used as
proof of current format: it legitimately predates these repairs.

Exported **256 packages: 10 Projects, 228 Backups, 18 Trash**. Every relative path and per-package
byte count matched the device index: **3,180 package files / 567,855,190 bytes**. A second device
index had identical paths, titles and sizes. Index-only export then cleared the temporary device
copies; the app was relaunched normally. Export evidence: `~/PaintWork/s51-cleanup/current-library/`.

A temporary simulator test used current production decoders/validators, never the repair services,
against every package: **2,181 cels, 1,565 vector sidecars, 95,350 strokes, 1,955 fills, 93 streams**.
There were no animation/interpolation sidecars in this library; those formats remain covered by
logic/UI qualification. **Zero decode failures, zero pending repair conditions**, including semantic
pose conditions and ignored retired fields. Input SHA inventory before/after was identical across
3,182 files / 568,016,132 bytes including the index/log. Temporary audit source was restored byte-exact.

## Qualification

Focused retirement logic: 117/117; latest current-stream/storage/restore gates: 25/25. Four deliberate
validation faults went red, and restored source passed. Actual exporter source and exact new XCTest
methods: Mac baseline/restored 4/4, five deliberate faults red. Raw logs remain under
`~/PaintWork/s51-cleanup/{repair-qualification,export-qualification}/`.

Final fast **Debug and Release each passed 5,251 total = 5,247 passed + 4 skipped**, zero failures,
matching the 254-class static census. Full-suite static census is 5,833; three private static
`testBrush` factories are excluded. Both UI lints pass (85 symbols/137 helpers); PBX has 1,314 unique
object definitions and passes plutil.

Release UI **3/3 passed**: `GalleryRecoveryUITests` (automatic backup recovery and Recently Deleted
restore), plus `TransformKeysSurviveUITests` (Move keys, bake beneath them, save and cold reopen).
All three retained keyframe screenshots were reviewed: Move box with diamonds, keyed picture after
bake and the changed picture at the reopened second key. Original Release app gallery was also
reviewed on an owned iPad9 simulator at1080×810pt: header, actions, scene tile/title/date fully visible.
Native raw and2160×1620 orientation-only view are retained; no test adapter or rebuild was needed.
Both owned simulators were deleted after qualification.

The full UI suite and physical gestures were not repeated for this cleanup. The prior unchanged
Liquify/input/rendering qualification remains indexed under `~/PaintWork/s50-liquify/`; this change
alters saved-file startup/restore validation and the diagnostic copy helper. Every tracked source,
resource and project file (723) is frozen for final device-build comparison. No temporary audit or
orientation adapter remains in the source.

## Deployment and checkpoint

Merged/pushed runtime cleanup in `bcd7a6af`. Normal Release clean/build succeeded; all723 frozen files
match, strict deep signature verifies, profile expires2026-10-30T00:18:54Z (October29 evening Toronto),
over six days remaining at install. Installed `Starg.PaintSoftware` without uninstall/reset. iOS denied
the initial launch solely because the device locked; after the owner unlocked, normal launch with
**no test arguments** succeeded and **PID53501 was observed alive**. Both raw launch attempts remain
in `~/PaintWork/s51-cleanup/final-release/` with install/signature/status records.

Owner is now asleep; no more device interaction remains. The completed cleanup item was removed whole
from TODO in the runtime merge. All remaining asks are deferred or await owner participation/briefs.
