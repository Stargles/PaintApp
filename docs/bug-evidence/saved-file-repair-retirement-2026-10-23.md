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

Final fast Debug/Release and recovery/keyframe UI are pending. Static census is 5,251 fast tests in
254 classes and 5,833 full-suite tests; three private static `testBrush` factories are excluded.
