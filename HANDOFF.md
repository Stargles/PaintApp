# Handoff

## Start the next session — Claude Code

From `/Users/juliapark/Desktop/Kevin.P/PaintSoftware`, use this prompt:

> Continue PaintSoftware from HANDOFF.md. Read AGENTS.md, CLAUDE.md, TODO.md and BUGS.md and verify
> `main` equals `origin/main`. Start with the owner's re-test of the November 17 build on their
> iPad (Test1: Undo lag, circle-and-line Fill, rapid draw/Undo, orange bars on entering). Then the
> twelve UI tests red on old `main` too, raster Undo pricing, and the open audit findings in
> TODO.md. Use focused delegation, keep TODO.md and HANDOFF.md current, and brief the owner in
> terms of what they see in PaintApp.

## Sign-off — November 17, 2026, Toronto

- **The November 16 failures are fixed on `main`** (TODO.md's first item has the list): the
  display server is no longer handed a canvas-sized picture per edit (the backboardd Jetsam
  behind the black-outs), the bake reuses its band memo (orange bars), Undo trims history to its
  budget with a notice instead of wiping it, Fill covers ink enclosed by the region (the owner's
  circle-and-line), the recorder logs tool settings, and a Move's lift repairs only what was lifted.
- **Gates at `d08d18a5`:** Debug and Release fast tiers 5,679 passed + 4 skipped each; the first
  full UI run (on the 13" simulator, which fails the 1080×810 size premises — use an iPad 9th
  generation simulator for the UI suite) left 33 reds; re-run serially on a fresh iPad 9 simulator
  with the one extra Fill red the worker found, 12 remain and all 12 are red on old `main` with
  the same message (TODO.md item). Four Fill regressions found on the way were fixed in `10f65379`.
- **Device stress on the owner's iPad passed** — `PaintSoftwareUITests/DeviceStressUITests.swift`,
  opt-in with `PAINTAPP_DEVICE_STRESS=1`, creates and trashes its own `ZZ-stress-*` folder and
  scene, never resets settings or libraries. Log: `~/PaintWork/nov17-device-stress/device-run3.log`.
- **Installed on the iPad 2026-11-17 (Toronto, evening)**: signed Release `9792e799` (binary UUID
  `0A93A076-21CE-329D-88CE-1FFC3BE90D1B`, profile through Nov 20 07:09 UTC) from
  `~/PaintWork/crash-20261111/device-fresh-9792e799-Release/`; `resign_state` updated. The integrated
  `tmp/*` branches are deleted and archived in `~/PaintWork/archive/refs-2026-11-17.bundle`.
- **Lessons:** the Release optimiser may free a never-read `var` at its last use — hold test pins
  with `withExtendedLifetime`; on the real iPad the number pad covers the size fields, so a device
  harness hides the keyboard between fields; "Timed out while enabling automation mode" is the lock
  screen.

TODO.md tracks outstanding work and owner rulings. Older checkpoints are in `git log -p HANDOFF.md`.

### November 15 continuation

**Original checkpoint at 02:08 Toronto.** Resume the approved
perspective correction first. The clean worktree is `~/PaintWork/PaintApp-nov15-parallax-fit`,
branch `tmp/nov15-parallax-fit` at `2907dc4b`. It has no edits or owned simulator. In
`TransformLayerMode.parallaxMap`, compute the fractional projective component relative to
the authored box origin and restore world coordinates. Preserve zero/full shares and the
affine control. Then remove the Parallax exclusion in `CanvasManager+Document`'s existing
resize transport, replace the temporary preserve-old assertion in `CanvasResizeLogicTests`,
and verify visible 400×200 and 600×200 Fit examples. Existing packages stay intact.
Analytic inputs, rendered comparison and prior compositor fixture links are in
`~/PaintWork/nov15-parallax-evidence/README.txt`.


- Owner asked to continue through all actionable work. CoreDevice confirmed the iPad is paired and
  still requires a recent unlock at 02:06 Toronto. `01fb0fe7` is the latest verified signed Release.
  Its profile remains valid through Nov 20 02:09. It meets the usual five-day install floor through
  Nov 15 02:09. The owner was told about that window. No device write occurred.
- Preserve the separate product and Desktop record histories. The previous exact release review
  with current notes is `ee98a190`. Git's read-only push preview confirms that review can
  fast-forward the shared branch. The owner's history decision remains pending.
- Old View failure reproduced on exact source at both nested folder and layer after reopen.
  Fix `d5ff1463` repairs preset and saved scene independently. All 63 focused checks passed.
  The old condition failed both intended reopen assertions and the restored check passed.
  The disposable cold Gallery proof passed. It opened older tracked artwork, selected the
  old View and showed its group again with the same ink restored. The older tracked drawing
  was copied into a reconstructed legacy View manifest. Inspected restored blue ink in
  `cold/attachments/F61BACD9-69B2-4F6D-828E-B85E61FC00F1.png` under the evidence directory.
  Owner packages remain untouched.
  Evidence: `~/PaintWork/nov15-legacy-view-evidence/`.
- Resize candidate `ff0a5e94` covers ordinary and stored container pose and Shake transport,
  including a mode-switch control. Active Parallax geometry retains the previous behavior.
  Exact Debug passed all 56 logic cases and the new cold Resize gesture. Inspected both landscape
  captures showing the two positions and keys. Five other unchanged cold workflows passed
  on identical production source. The four deliberate reverse cases failed as intended
  and all four passed restored. The picture of the old fault showed half the expected travel.
  Fractional perspective remains separate: an example holds the same saved scene values
  but must change its picture to correct Fit; a wider valid full-strength pose makes the
  current half-share blend undefined. Owner answered “no scenes need to be preserved” to
  the A/B appearance choice. Proceed with the shared Fit-safe blend and test existing stored
  inputs against the new math. Keep actual packages intact.
  Evidence: `~/PaintWork/nov15-parallax-evidence/`.
- Undo diagnostic `7b27c469` passed 26 focused logic controls, three existing recorder UI checks,
  the prior green-stream UI, and its own landscape cold check. The latter recorded exactly
  two accepts on one cel, a deferred nonempty replacement and immediate empty assignment.
  The unattended Probe also captured two consecutive deferred assignments. This measures the
  app's accepted base before physical presentation. Device timing and attribution remain open.
  Evidence: `~/PaintWork/nov15-undo-probe-evidence/`.
- Prepared composite branch `tmp/nov15-release-gate` at `2907dc4b` from the old-View fix, Resize
  and recorder. Both linters passed. The owner chose the perspective fix after this assembly,
  so include it before running the release gates. The superseded 2907 cold run and its
  conditional signing wait were cancelled at the owner's decision. Its incomplete result
  is not a gate. The owned simulator was deleted, and no owned job remains.
  Rerun the focused cases and an exact combined cold/Debug/Release gate after implementation.
  Scripts and cancelled result: `~/PaintWork/nov15-release-evidence/`.
- Windows still rejects the configured SSH key. Device and shared-repository writes await the
  actual readiness/decisions. No new physical freeze or crash evidence.

### November 14 evening continuation

- The iPad was paired but locked at 17:21 Toronto. Read-only inventory at 17:22 found the same
  two recordings and all 197 crash paths unchanged. No new failure flight or system report.
  Signed `00cb237b` is ready; asked for saved Gallery and unlock. Continue the current-source
  rendering and brush audit while physical access is pending.
- The recorder can currently miss a moving pair with intact bindings and zero view writes.
  Track the automatic evidence gap in TODO. Undo's existing two-second aggregate
  also cannot distinguish a slow raster from a late base picture. Scope a correlated
  accepted-picture event before changing either production workflow.
- Source confirmed a separate unbounded stream timing array between displayed frames.
  Preserve its exact count/mean/max output using fixed-size accumulation.
- Exact evening batch passed 12/13, including all playback/bake and Liquify cases, brush
  curve drag, and the other three mask workflows. Colour Mask's held new stroke failed
  before lift. The video shows the ordinary stroke clipped, then editable Shape Hold paint
  extending beyond the mask. The ordinary continuously moving Brush control passed on unchanged
  production code at `3992374b`, with the held samples and final visible pixels inspected.
  `31e66383` transfers the same resolved brush mask to the editable shape's ink host and clears
  it with the draft. All 53 focused checks passed. Inspected the clipped editable line
  with the guide and endpoint visible outside the mask. Missing clip and stale clip each failed
  their intended native pixel checks. Restored green and a separate 1080×810 pt landscape
  witness passed. All component simulators have been deleted.
  Evidence: `~/PaintWork/nov14-bounded-thumbnail-evidence/evening-ui/mask-triage/`.
- Combined exact source `01fb0fe7` completed the simulator gates. It includes masked Shape Hold,
  the stream/edit worker split, bounded tick summary, extra automatic freeze evidence, and the
  already qualified damaged-text and Mend All fixture changes. All 19 cold workflows passed,
  with no missing methods. Inspected clipped edit handles, the recorded red fill with its
  reference hidden, and green-stream Undo. Both Debug and Release passed 5,647 plus four
  opt-in skips with every ID matched. The owned simulator was deleted. Signed arm64 Release
  `01fb0fe7` verifies, UUID `0244C786-A5F5-381C-8C23-C89BC5B09295`, same app identity and paired
  device set, profile through Nov 20 02:09 Toronto. It is staged under
  `~/PaintWork/crash-20261111/device-fresh-01fb0fe7-Release/`. Installation awaits saved Gallery
  and unlock. Exact opt-in Release passed 2/2 Fill and 1/1 isolated Lens. Mend All changed the
  300- and 1,000-cel light fixtures in ~2.34/8.19 s with ~0.5/0.0 MB sampled footprint increase.
  Interactive Mend On/Off took ~95/5 ms and ~0.3/0.2 MB in the 64² fixture. Lens returned the
  changed 2048×1024 pixels in 20–22 ms; same-run radius-zero and Gaussian were 12 and 22 ms.
  These figures are simulator measurements. The opt-in simulator was also deleted.
  The exact project has 1,335 unique top-level PBX objects
  and zero compiler warnings on changed app lines. Static fast selection is 5,651 cases.
  Canonical has isolated ref `tmp/nov14-evening-gate` and a records-only review at `ee98a190`.
  The review has identical app and test trees and preserves both historical queues. The
  two-way ref and three-way conflict receipts are in `~/PaintWork/nov14-audit-evidence/integration/`.
  Native evidence: `~/PaintWork/nov14-evening-evidence/`.
- Stream timing summary `3c939109` passed 26 focused Debug checks, including visible On Top
  stream placement. It stores count, sum and peak instead of the sample array. The deliberate
  peak fault reached its native assertion and passed restored. The other two counters also
  have source-level fault witnesses. The automatic capture component `9b20cd04` passed 25
  Debug checks, and a cold healthy pinch visibly moved the ink with 24 navigation writes
  and no false miss. With intact bindings and deliberate zero writes, the same cold path
  silently saved four qualifying samples and 40 pt relative travel before manual save.
  Exact stream/Undo `ad1d6160` visibly removed the newest stroke while the next On Top frame
  was still waiting. The old alias failed the edit-admission logic test, and the cold UI
  passed in both layouts. Physical Undo timing stays open. The iPad still required its passcode
  at 19:02 and its recording list was still unchanged. The later read-only system crash listing
  had no added paths against the 17:22 baseline. Device remains on `8214421f`. The repository
  selection and saved Gallery/unlock are pending with the owner. Retained signed releases, source
  refs, result bundles and screenshots. Cleaned ~4.5 GiB of owned compiler output; 47 GiB free.

### November 14 active work

- Recovered the owner's November 14 circle/line Mend Gaps recording. It confirms the cross-layer
  Pencil workflow on installed `8214421f`, with varied line pressure and the reference hidden
  after Fill. Fill settings and brush width are absent. The owner's active scene is in Files
  outside the app container. Reproduced a 12 px pressure-stroke failure using the trace geometry:
  repeated same-dab support checks used the entire work budget. Candidate `a6ae7c6c` passed
  32 focused logic checks and all five earlier cold Mend cases. The recorded-layout cold workflow
  passed at `bb307723`; inspected the owner-size landscape picture with the line layer hidden.
  The first 12 px fix still refused 20 px and cost 218 ms in optimized Release.
  The refined source replaces repeated walks with support-row unions and exact contact runs.
  The trace fixture used 10.6M work at 12 px and 24.1M at 20 px (previous cap 64M). The
  main line fills at both widths, outside stays identical and a wide ambiguous turn stays clear.
  Assembly `69b6b5c9` adds the verified Gallery tests and measures both widths in its Release gate.
  Focused exact source passed 32 logic checks and the landscape cold replay. The old scan,
  an exterior leak and a protected-turn leak failed their intended assertions. All seven
  combined cold workflows passed, including the recorded Mend, open-lasso Move and five
  compatibility paths. Exact fast Debug and Release both passed 5637 tests with four opt-in skips and
  reconciled method IDs. Release Mend measured ~68 ms at 12 px and ~122 ms at 20 px, with
  ~2 ms for a Reach edit, on the simulator. Signed arm64 Release `69b6b5c9` is ready,
  UUID `CA7C86DB-0149-3D91-86A7-5F402604F13A`. Profile expires Nov 20 02:09:17 Toronto.
  The connected iPad is locked; asked the owner for saved Gallery readiness. No install yet.
  The 02:58 listing showed no new automatic freeze flight. Physical acceptance remains open.
  The 15-test Fill Object class and drawn keyed Canvas Resize passed on the same SHA.
  Inspected the gradient after Freeform and the posed drawing after resize. See
  `~/PaintWork/nov14-release-evidence/additional-cold-69b6b5c9a574a71610be2ce17d34e2591a4762d3/`.
- The iPad's November 14 listing showed no new automatic flight since `8214421f` was installed.
  A November 13 03:31 SystemMemoryReset names no killed process; the app was suspended.
  Details and original report are in TODO.
- Mac had no stale test runner or booted simulator at the initial check and reported 63% available
  memory. Left the owner's open software untouched.

- The documented Flip vector omission was reproduced in sample geometry and the public
  Actions editor. `393fa256` passed all 62 in the touched classes, including reflected stored
  poses, the native Liquify field, malformed Fill refusal and drawn pixels. Inspected the
  reflected rectangle. The old mapping/refusal fault failed all five new checks and was restored.
- Missing derived timeline thumbnails were reproduced after real save/load. `98e94d9f`
  passed both new logic tests and public cold reopen. The old guard failed the actual tile
  test; using captured identity wrongly installed a stale pose, as expected. Inspected the
  difference in the drawn timeline thumbnail. The full Project Save class passed on identical
  production source. Combined audit candidate `f1ee828e` passed all eight exact cold workflows;
  inspected the Flip and restored ink/tile screenshots. Exact Debug and Release each passed
  5,643 plus four opt-in skips, with all method IDs reconciled. Both UI linters and 1,308 unique
  PBX declarations passed. The test simulator was deleted. Retain the complete isolated source
  at canonical `tmp/audit-flip-thumbnail-20261114`. Successful Flip retains the old history clear
  and canvas-relative live styling, plus the shared vector mirror behavior. The newer signed
  `f1ee828e` Release includes Mend/Lasso, Flip and restored timeline tiles. Strict codesign, same
  team/device set, and profile until Nov 20 02:09:17 Toronto verified, UUID
  `99BF68D9-D346-38F6-B36F-1D566BF331AA`. The iPad is still on `8214421f`, pending saved Gallery
  and unlock. Both signed candidates remain pinned. Shared-main transfer is a separate open item.

### iPad update

- Latest signed arm64 candidate `00cb237bff09c9dca3c762637b11b04351bc9bfd` passed exact
  Debug/Release and 13 cold controls. Includes Mend, open Lasso, vector Flip, restored timeline
  thumbnails and smaller intermediates. All 13 in the touched Mend and open-lasso classes
  passed, plus four additional cold checks for off-frame Undo thumbnails, menu pan, Lens Blur,
  and export Cancel returning to drawing. Total 30 exact cold checks. The outline replay
  screenshot and source receipt are in `~/PaintWork/nov14-bounded-thumbnail-evidence/final-mend-ui/`.
  Strict codesign verified, UUID `72E591F6-B10B-3FA4-BAD4-29616CD4665B`; Apple
  profile through Nov 20 02:09:17 Toronto. Evidence and app path:
  `~/PaintWork/nov14-bounded-thumbnail-evidence/exact-00cb237bff09c9dca3c762637b11b04351bc9bfd/device-build.txt`.
  At 06:02 Toronto the iPad was locked and its recordings contained the old flight and the
  circle/line recording, with no newer automatic flight. It still runs the older build below.
  Wait for saved Gallery and unlock before install. No app data changed.

- Installed release adds recorder commit `8214421f8cd8425b48368d638346629fc8eec8f8`;
  qualified source is held by both repositories. The pre-recorder fallback
  `4dec214579125fb1ff55f4399be799cef9b7d71f` is pinned at canonical
  `tmp/qualified-device-20261113` and `~/PaintWork/PaintApp-qualified-followthrough-20261112`.
  Debug and Release each passed 5629 with 4 opt-in skips and no failures. Nine touched UI and
  five exact compatibility checks passed, with inspected owner-size pictures and exact result IDs.
  Results: `~/PaintWork/qualified-followthrough-evidence/exact-4dec214579125fb1ff55f4399be799cef9b7d71f/`.
- Includes live vector Liquify, cross-layer Mend, rapid Undo and stream/Fill display improvements,
  bounded native Fill references, keyed resize, slider and Move recording, and bounded graph
  backing preview. Masked, constrained and complex graph previews keep the existing striped path.
- Installed and normal-launched `8214421f` at 02:12 Toronto November 13. Strict signature
  verified, iPad connected/unlocked and work saved in Gallery. Profile expires November 20
  at 02:09:17 Toronto. CoreDevice verified the installed bundle path and live PID 2196;
  local executable UUID `F18D399E-AC10-3B76-ADE6-5CCD61D92AE7`. Renewal state updated after
  install to exact SHA, signed artifact, and UTC profile dates. Evidence files
  `~/PaintWork/crash-20261111/device-fresh-8214421f-*`. No artwork or settings touched.
- Owner's original Test one-tap Move case still needs physical confirmation. Exact old recording
  is gone; preserved Git reports show lifts that quickly canceled. The image-ownership fix is
  installed and had a cold one-tap regression with a failing old guard. TODO has the safe
  zero-nudge cancel procedure. Physical workload checks remain for rapid edit/stream, settled
  Undo, Mend and Apple Pencil Liquify. Preserve artwork and brush library.

### Freeze and crash

- No more manual freeze reproduction or recording requests to Kevin. Read-only repair #23 from
  00:13:33 Toronto shows UIKit canceled and reissued one moving finger, losing pinch, rotation
  and stroke bindings. A previous similar event kept pan; fresh-start misses have a distinct
  reset pattern. The trace's transform labels are cached and cannot show applied movement or
  whether handlers ran. Timer timing fix is separate. No root fix is established yet.
- Automatic recorder `8214421f` passed automatic same-editor save, exact #23 replay, and
  three cold recorder workflows. A healthy pinch logged 29 writes and changed scale/center
  with manual capture off. Debug/Release each passed 5633 and skipped 4 on identical app
  source `d4ac2754`, and five exact preinstall checks passed. Test-only descendant passed
  the added timer witness and intended timer-disabled failure. Restored clean, simulator
  deleted. Evidence: `~/PaintWork/automatic-freeze-recorder-evidence/readout.md`.
  Installed at 02:12. Retrieve fresh automatic evidence independently. Root cause remains open.
  Installed ancestor `45e067a5` gives automatic and manual files unique same-second names.
- Freeze evidence: `~/PaintWork/crash-20261111/freeze-flights/readout-20261113-0014.md`.
  Keep recovery until the underlying input failure is fixed and verified.
- The Nov 7 black-screen recording matches a display-service memory termination (`backboardd`
  at about 1859 MiB). It does not identify allocation ownership or explain later Fill. Candidate
  avoids known redundant 5000² stream and Fill pictures; no physical memory result yet.
  Settled Undo retains one ~95 MiB full-image copy to preserve exterior pixels. The incident
  recording cannot associate its delay with that copy. Compare the same workload stream off
  versus moving On Top before closing either report. Matched 5000² simulator control
  `b73829b0` passed six settled Undos, retaining the earlier stroke. Raster deltas were 1/0/1
  in each arm. Pictures inspected. This test does not measure physical Pencil/UI latency.
  Evidence: `nov14-release-evidence/undo-control-final/` and `crash-20261111/nov14-readout.md`.

### Remaining checks

- Installed ancestry and exact tests confirm the late slider fix (`07ea65a0`), late Move
  fix (`ca1e7041`) and bounded graph preview (`4dec2145`) shipped in `8214421f`. Their
  earlier promotion-only checklist entries are closed.
- Cold Gallery qualification is complete at test-only `5eb893c3` on qualified `ef335c4b`.
  A damaged scene with no backup showed No Backup and kept the exact original. A second scene
  reopened with the exact backup, visible Multiply Mix and its original damaged file in Trash.
  Restoring the former silent fallback made both cases fail the intended assertions.
  Evidence: `~/PaintWork/cold-gallery-mix-recovery-evidence/`.
- Cold simultaneous pan/pinch worked with the active Brush layer both visible and hidden on
  unchanged app code. The earlier staggered attempt failed on the visible control first.
  No gesture behavior was changed.
- Open-lasso Move is qualified at exact `ef335c4bc79dd6d3f8767cc1593b2be2cbeeae56`
  (canonical `tmp/qualified-open-lasso-20261113`). It closes the U through existing lasso
  rules and lifts only enclosed ink. Both combined fast tiers passed 5636 with 4 opt-in
  skips and no failures. The unchanged feature patch passed 19 logic and eight cold UI
  checks, and the old ordering failed four intended assertions. Inspected full landscape
  pictures in `~/PaintWork/open-lasso-move-evidence/owner-size/`. Awaiting the next iPad update.
- Reclaimed 6.8 GiB of inactive compiler caches in PaintWork. Kept signed builds, test results,
  screenshots and diagnostic files.
- Bake residency is proven on test-only `e6598ef3`: 13 Debug, full cold class, six frames with
  zero resident native source bytes at publication and 49,152-byte peak. Fault independently
  failed both byte limits. Results in `~/PaintWork/video-bake-residency-evidence/`.
- Closed historical duplicate TODO summaries: the point-only vector Liquify conversion was
  owner-confirmed and the temporary converter was removed in installed `ec62d712`; live Pencil
  acceptance remains open. High-density To Cross erasing is closed at the owner's instruction;
  keep the newer rapid-edit/stream restart open as a separate incident. The newest-backup
  policy is installed. The old seven-day copy-only APFS controlled workload found 12,562,432
  additional allocated bytes for nine retained points with repeated saves. That historical
  measure covers the copied fixture, not the whole original library or iPad. The evidence
  directory was lost in the earlier cleanup; retained-source receipt is the October 23 saving
  section at `~/PaintApp` branch commit `e17cb8fb`. No new physical measurement is pending for
  that closed behavior.
- Reclaimed a further ~1.59 GiB of inactive compiler intermediates; kept the built products,
  both signed releases and test evidence. The 03:40 read-only recording list showed no newer
  automatic freeze flight.
- Windows SSH key rejected; Desktop Commander offline. UDP discovery silence is inconclusive.
  The TCP accept replaces any active iPad connection. Keep real Windows-link verification queued.
- Canonical main and installed-code history diverge after `afd2030c`. Canonical local changes
  are records-only, while the qualified code includes the existing installed lineage. Preserve
  both refs and remote state. Joining both histories conflicts with the no-merge-commit rule.
  November 14 preview shows three document conflicts and 656 candidate commits since the base.
  The iPad renewer refuses unrelated histories. TODO records a linear continuation of the release
  with the canonical record content and a named preservation ref for canonical local commits.
  Local review branch `tmp/nov14-promotion-review` at `646402f8` has the signed `00cb237b` app tree,
  agreed documents and the two separately qualified test-only revisions. The remote remains at
  `afd2030c`; the existing local main and renewer settings were preserved.
- `07b61ce5` already transfers the matching presented Fill surface into held ink. The fallback
  uses the prepared bitmap. Exact `f1ee828e` passed all 12 follow-up tests: the full Tap selection
  and Glare classes, textured eraser Undo/Redo, the moving-stream Fill and one translucent coat
  retained through commit. Static IDs reconciled.
  Evidence: `~/PaintWork/nov14-audit-evidence/exact-f1ee828e865e68fcb8eda4a7f7c772a39f6e9a21/follow-up/`.
  Physical crash attribution remains open.
- `244dec55` passed five iPad 9 brush tests. The three new test-only cases draw in both
  landscape directions and portrait, with correct pictures inspected. Existing Hook tests ran
  after replacing the narrow title-bar setup tap with the public Brush toggle. Bypassing rotation
  failed both landscapes at the intended pixel assertions; translating touches failed the portrait
  path. Restored the tests and removed the owned simulator. No shared helper or app code changed.
  Source pinned on canonical `tmp/verified-touch-orientation-20261114`. Evidence:
  `~/PaintWork/touch-orientation-control-evidence/`. This scope did not replay the old held Shape.
- Corrected test-only `17603799` ran the existing optimized Mend benchmark from a real bucket
  contour on identical app source. Both tests passed. Mend All repaired 300 light 72×72 cels
  in 1.769 s (+1.5 MiB sampled process footprint) and 1,000 in 6.183 s (+1.8 MiB). The three-cel
  warm-up and first/middle/last drawn probes passed; one Undo/Redo restored every path, and the
  one-byte Undo budget left each cel/history untouched. The old hand-notched fixture left bare
  contacts outside actual ink, so it correctly returned unchanged. These timings and footprint
  deltas are simulator fixture measurements only.
  The associated interactive 64×64 trial was ~4/63 ms with Mend off/on. The earlier same-app
  separate point-only Liquify path check mapped 2,560 stored points, changing 12 of 81 strokes
  with fixed width and exact pixels at an independent distant control; warm median 138 ms under
  that simulator setup. Do not present this as physical Apple Pencil latency.
  Results: `~/PaintWork/mend-all-cost-fixture-evidence/` and the previous audit opt-in bundle.
- Damaged-text save and restore passed at test-only `4da0c314`, with identical app source to
  signed `f1ee828e`. Used the committed actual old writer package and removed only its text
  string in a disposable copy. Both original blue strokes and new red ink survived the
  Cancel/Versions/Restore route, and all four pre-restore package bytes matched the copy in
  Recently Deleted. Inspected the warning and restored ink. The first run stopped at the
  brush size fixture; the test-only 3-point setup granularity kept all drawn checks intact.
  Existing storage logic independently asserts original bytes before restore. Neither
  old-code mutation nor physical iPad were repeated for this check.
  Evidence: `~/PaintWork/nov14-audit-evidence/exact-4da0c314b01c4be087dd74298d1aafa6619b9fdf/strict-text/`.
- Derived-thumbnail sizing is the next separate memory seam. The live provider currently
  has no output bounds for its posed/video/interpolation callers, although the thumbnail
  consumer already requests a 480-pixel box. Candidate `12354add` reuses that request end to
  end. Focused normal 20/20, including odd-sized pose, interpolation and video output,
  unaffected native interpolation and two save/backfill controls. All four deliberate
  faults reached their intended assertions, and the restored test passed. Public cold tile
  passed with a visible posed drawing in the timeline and on the canvas. The combined
  `00cb237b` gate (source plus test-only orientation controls) passed all 13 exact cold
  workflows. Exact Debug and Release each passed 5,644 plus four opt-in skips, with all IDs
  reconciled. The owned simulator was deleted. This bounds intermediates to 480×240 in the
  959×479 fixture for pose, video and interpolation and preserves the old final tile extent.
  Minor edge antialiasing can differ inside the tile; artwork and full-size rendering use
  the original path. No physical footprint measurement. The updated signed build is listed
  above. See `~/PaintWork/nov14-bounded-thumbnail-evidence/`.
- Current native work is complete on the signed candidate. The broad audit and full UI suite
  are not finished. The high-priority remaining evidence is physical Mend/Liquify/Undo and
  rapid-edit behavior with a real stream, a new automatic flight for the intermittent touch
  loss, and Windows host access. The archive/current-library and deferred interpolation
  items remain on the detailed queue.
- About 49 GiB free after deleting only owned inactive compiler caches. No owned simulator
  remains booted. No personal applications closed.
- See TODO for the remaining audit scope and deferred feature requests.
  Preserve primary results and signed builds. Remove owned generated caches when inactive.

## Resume rules

Read AGENTS.md, CLAUDE.md and TODO.md. Keep this checkpoint current and keep tasks in TODO.
Use task-appropriate model and effort. Delegate coherent work through verification where it saves
effort. Run quick checks directly and avoid redundant handoffs or reviewer agents. Root owns
priorities, acceptance, the shared native lane and release decisions.
