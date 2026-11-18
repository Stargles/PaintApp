# TODO

## Latest owner requests — resumed 2026-11-11

**Every task ALWAYS goes in TODO.md**, including deferred requests and new reports on old bugs.
HANDOFF.md is a navigation/checkpoint document, never the only record of an outstanding task.
**Resumed November 12.** The combined candidate passed both simulator gates. See HANDOFF.md for signing and the physical iPad checks.

- [ ] **November 16 iPad test of `fecc1a8f` failed (owner, Test1, 5000², 5 vector layers).**
  Undo lag still there; the circle-and-line Fill gap still there; rapid draw→Undo and rapid
  drawing each blacked out / restarted the iPad; entering a document shows orange bars ~10 s per
  frame ("not like this before"). Eraser seemed fine. Owner: a build this faulty must never reach
  the iPad; fix everything, audit the repo for spaghetti, and keep going without stopping.
  Evidence `~/PaintWork/nov16-owner-test/`: three JetsamEvents 18:18–18:20 all kill
  **backboardd at its 1,850 MiB per-process limit** (PaintSoftware 626–816 MiB) — the display
  server is drowning in surfaces the app hands it. Recordings: Undo press→base assigned 0.71 s;
  every edit re-rasterizes a whole 5000² vector cel off-main (350–640 ms each, 19 in 2 s during
  rapid strokes); bakeComposite 2.2–7.4 s per frame.
  Owner details: the Fill test line was **Rough Ink at 0.1%**, pressure-varying (thicker near the
  end); the recorder captured no brush or Fill settings — **the recorder must log active tool
  settings** (preset, size, pressure, Fill/Mend/Reach) — owner calls that gap a failure itself.
  Owner also recalls **Fill latency and a crash when rapidly filling several regions** (no
  recording); treat as the same full-size-surface family until measured otherwise.
  Owner has retired Codex for now; the owner's concern is less-visible defects of the same kind —
  the repo audit must look for them, not only for structure.
  **Nov 17 — fixed, gated, merged to `main` and installed; awaiting the owner's re-test.**
  Render-server pinning + 0.25 s render pacing (surfaces), band-from-memo bake (orange bars),
  Undo trim that never wipes history + notice, Fill window at scale 1 + recorder tool settings,
  enclosed-ink Fill (owner's line: 0 bare pixels, 1.52→0.54 s simulator Release, measured before
  `10f65379` made absorb cheaper and also cover a stem attached to the outline), and Move lift
  repairing only the lifted footprint (91→31 ms simulator Release). Gates at `d08d18a5`: Debug and
  Release fast tiers each 5,679 passed + 4 skipped; the 34 UI tests red in the first full run,
  re-run serially on a fresh iPad 9 simulator, left 12 reds, every one also red with the same
  message on old main `6464761a` (item below). **On the owner's iPad** (Debug, opt-in
  `DeviceStressUITests`, 5000² + 5 vector layers, owned fixtures trashed afterwards): 20 strokes
  then 20 Undos ×2, 30 rapid strokes, a grid + 10 fills — no crash, no new Jetsam/backboardd log;
  20 Undos took ~9.5 s of XCUITest-paced taps. Owner to confirm by hand: Undo lag, the circle-and-
  line Fill, rapid draw/Undo, orange bars on entering Test1.
- [ ] **Fix the November 16 audit findings** ([docs/AUDIT-2026-11-16.md](docs/AUDIT-2026-11-16.md), 18
  ranked). The repeating defect: RAM-derived budgets (192 MiB on iPad 9) tested at 2048² that
  silently decline, scale down or drop history at the owner's 5000² scene. **Done Nov 17:** Undo
  trim no longer empties the stack (notice instead); Fill covers enclosed ink without the slow
  certificate; Move lift repairs only the lifted footprint; render pacing for the deferred vector
  installs. **Open:** ~20 silent `hasHeadroom … return nil` refusals need a notice; canvas-size
  ceiling measures the app, not backboardd's 1,850 MiB; `CALayer.contents` installs still outside
  the paced path; raster thumbnails at canvas size; three bitmaps per vector cel; unbounded static
  caches; commit/un-suppress still invalidates `.everything`; `renderIsolated` on the main thread.
  Add a gated 5000²×5-layer fixture for every budget consumer (`DeviceStressUITests` is the device half).
- [ ] **`MoveBoxPrecisionUITests.testAFingerPressedBesideAVectorBoxDragMakesItAFifthAsFarAndLeavesTheCanvasAlone`
  fails at its XCTUnwrap (line 54)** on an iPad 9 simulator (seen Nov 17 while fixing the twelve
  old UI reds, which are now all fixed: ten stale tests, a missing Photos fixture, and one real
  defect — a graph key held to an axis jumped diagonally on release). Triage: stale vs real.
- [ ] **Raster Undo at 5000² is one whole-cel step (190.7 MB) against the iPad 9's 192 MB
  budget**, so raster layers keep only the protected minimum of history. Price raster steps by
  their dirty tiles, as vector steps already are (0.11 MB a stroke).
- [ ] **Fix severe Undo latency.** Owner reports drawing is responsive after the latest Release
  install (`d4d59f6bc261d23366c8e713ecab96353fe0183c`), but Undo still has “enormous latency” despite an
  earlier fix. Reproduce and compare that specific path first; correct the root cause efficiently.
  Do not start another broad audit or testing/storage framework.
  Source review at `6c0b37e6` found the known full-image copy for settled Undo's clipped
  repair (about 95 MiB per 5000² RGBA8 bitmap, before row padding). This preserves unchanged
  pixels in the current single-image renderer (PERFORMANCE.md §11.11b). Existing traces cannot
  attribute the owner's delay to this copy. On iPad, wait until the stroke lands and measure
  a single Undo per quiet interval, stream off versus a moving On Top stream, counting rasters
  and timing tap to ink disappearance. Only change the renderer if that comparison supports it.
  November 14 readout of the earlier Test1 footage: the last crash interval records a 6.58 ms Undo
  press next to three off-main vector rasters (up to 1038 ms). The separate latency recording
  has five brief Undo presses (max 1.82 ms) and four off-main rasters (max 567 ms). Rollups
  cannot map a raster or visible landing to one action. The available device Probe reports
  predate the current build. Cold 5000² simulator control `b73829b0` on unchanged app code
  verified three settled Undos per condition, always retaining the earlier stroke. Hidden and
  moving stream each recorded 1/0/1 raster increments; no stream-only excess in this fixture.
  The observed 570–827 ms includes XCTest tap and screenshot overhead and is not a physical
  latency measurement. Screens and results: `~/PaintWork/nov14-release-evidence/undo-control-final/`.
  Existing recording spans aggregate two seconds of work and lack the exact content identity
  and successful view update. Use the existing recorder to pair an Undo press with the actual
  vector replacement and accepted base picture for the edited cel, including cached and
  deferred paths. These timestamps reach the app's layer assignment, before physical screen
  presentation. Keep overhead low, unrelated edits separate, and compare stream and
  canvas-size controls before changing the renderer. Current source shows a stronger testable
  lead: On Top stream surface work and vector rendering use the same serial queue. A stream
  job can wait for a reusable IOSurface (up to 500 ms) ahead of a settled Undo render. Isolate
  that by controlling a held stream draw. Exact `ad1d6160` keeps one stream worker separate
  from the shared edit worker. A staged cold iPad 9 test shows two strokes over an already
  presented green stream, then Undo leaving one stroke over green while the next frame is
  still waiting, and finally the same drawing over blue. All 25 window logic tests passed.
  The shared-queue fault failed the controlled edit-admission test, while the cold UI also
  passed with the old queue and therefore proves drawn continuity only. Use the physical
  comparison to check whether the shared-worker delay was the one Kevin saw.
  Old traces:
  `~/PaintWork/crash-20261111/nov14-readout.md`.
- [ ] **Resolve intermittent whole-iPad failures during rapid edits.** Owner reports a black screen
  and brief restart during drawing → Undo → drawing. On November 11 he also reported a crash after
  repeated Fill. The observed crashes coincided with rapid activity and a running background stream.
  He could not reproduce it in limited recent testing. Compare the same workload with and without
  a running stream and correlate the recording with device diagnostics. Look for memory retained by
  stream decode/display, Undo, Fill, and baked frame ownership. Owner expects baked scenes to keep
  working memory bounded as artwork accumulates. The cause and relationship to Undo latency are open.
  Verify the repaired workflow and directly related drawing, erasing, Fill and Undo/Redo paths.
  The matching device report records a display-service memory termination. See HANDOFF.md for
  the verified correlation. Check native stream-host rebuilds first. Follow up on Fill's separate
  full-size reference image and preview-to-base handoff costs through the existing render owners.
  Preserve exact Fill pixels and measure before treating either path as the cause of a restart.
  Exact `6c0b37e6` source confirms a marked vector reference containing a stream (either
  placement) flattens a detached 5000² bitmap before drawing the actual small Fill window.
  This is about 95 MiB per source and pass; enlarging the bucket search can repeat it. The
  temporary bitmap is scoped to that pass and is not retained across Fills. Prove with an
  existing reference pixel fixture and total raster count, then reuse the clipped drawing
  seam with per-cel isolation and identical final pixels. `1893d84f` passed 34/34 including
  repeated cold Fill; both stream modes have exact bytes and no extra native raster. Faults
  reproduced the full-copy, eligibility, missing-stream and refusal failures. Integrated on
  follow-through `03831f79`; qualify its exact fast tiers and stream class next. No crash attribution.
  Displayed Fill surface reuse already shipped in `07b61ce5`: an exact presented render and clip
  transfer through UnlandedInk, while pending/mismatched fronts use the prepared bitmap. The
  native logic check asserts surface identity, clip, opacity, fallback and counted front bytes.
  This eliminates a duplicate upload when eligible, while the prepared bitmap still exists.
  No physical memory or crash attribution follows from that change.
  November 14 device inventory found a Nov 13 03:31 Toronto SystemMemoryReset report.
  The same PaintSoftware PID from the verified install was suspended at 153 MiB (430 MiB
  lifetime max). The report records reclaimable memory at 63% against a 65% threshold and names
  no killed process; it does not identify an editing crash or its cause. Original report:
  `~/PaintWork/crash-20261111/SystemMemoryReset-2026-11-13-033106.ips`.
  Retrieved, size-verified evidence (no investigation performed):
  `/Users/juliapark/PaintWork/recordings/2026-11-07/recording-20261107-221600.jsonl`, 192674 bytes,
  SHA256 `a667509c30962d5a7b54e012bef9f500f2f7bcb7d19c7e75f136baf971ed5590`.
  Earlier drawing/erasing-latency recording:
  `/Users/juliapark/PaintWork/recordings/2026-11-07/recording-20261107-202427.jsonl`, 145173 bytes,
  SHA256 `a479de0d1ccfb562408e89e25c01a2cf5e54ddbee50293aec1556cb3aad2ace1`.
- [ ] **Reproduce and fix the owner's cross-layer Mend Gaps case (November 11).** On the iPad,
  draw a circle and a short line inside it on one layer, then switch to another layer and Fill
  inside the circle. The fill leaves the line's footprint uncovered. With Mend Gaps on and Reach
  sufficient for that line, the same fill must cover beneath it while preserving the circle's
  outer boundary. Check the installed source and actual tool workflow before assuming a missing
  feature or building a second mending path. Keep real-time feedback and uncertain joins protected.
  Cold freehand circle and 6 px mark passed with Reach 12 and Edge Overlap 0 on the iPad 9
  simulator, including Mend Off/On and target-only pixels. A dense snapped outline reproduced
  the failure because the work estimate abandoned mending for the whole reference. Candidate
  `2c26812a` bounds the actual neighbour search within the existing safety budget. All 31 Mend
  logic tests and five cold UI workflows passed. Installed in `8214421f`.
  November 14: Kevin reproduced the circle-and-interior-line failure on the installed build
  and saved a recording. Recovered it read-only from the iPad:
  `~/PaintWork/mend-20261114/recording-20261114-011250-8B46A3AB-A1B8-46BD-B086-FB7DF742C06E.jsonl`.
  It confirms the installed build, Pencil circle then pressure-varying interior line, different
  target layer, fill tap and reference hidden afterward. Brush width and Fill settings are absent.
  The recorded paths with a 12 px pressure-varying Opaque Round brush reproduced the gap on
  `8214421f`: the per-dab neighbourhood scan exhausted the 64-million work limit before it could
  return support for any interior ink. Candidate `a6ae7c6c` avoids duplicate checks using the same
  coverage and work limits and passed 32 Mend logic tests, including untouched pixels away from
  the interior line, attached marks and uncertain joins. Five original cold routes passed. The
  new cold replay passed at `bb307723` and shows a solid fill with the reference hidden.
  In optimized Release, 12 px passed at Reach 12 with 39M bounded work and 4.45 MB charged.
  First Mend took roughly 218 ms; changing Reach reused the result (roughly 5 ms). The 20 px
  version exhausted 64M even at Reach 40. A work breakdown showed repeated contributor
  closure walks cost most. Querying once per support growth and deriving contacts from the
  same packed rows reduced charged work to 10.6M (12 px) and 24.1M (20 px), with 3.1/4.1 MB
  charged. Cut colours were identical outside the stroke. At 20 px the trace's early turn
  overlaps both valid and protected support, so it deliberately stays bare while the unambiguous
  main body is covered. Exact focused `479252be` passed 32 logic and one cold UI. Old scan,
  exterior leak and protected-turn leak each failed the intended assertion. Combined
  `69b6b5c9` passed seven cold workflows and both fast tiers (5637 passed, 4 opt-in skips each).
  Simulator Release first Mend was 68/122 ms at 12/20 px, with 1.8/2.0 ms for a reused Reach
  update. Signed `00cb237b` includes this exact fix, open-lasso Move, editable vector
  Flip and restored and smaller timeline thumbnails. Both mandatory fast tiers and 30 cold
  checks passed, including all 13 in the touched Mend/lasso classes and the actual recorded
  outline. The later signed `01fb0fe7` includes this same Mend fix and passed the recorded
  motion again. Both signatures verify. The iPad was locked at 19:02. Await saved Gallery and
  unlock. Real iPad confirmation remains open.
  Evidence: `~/PaintWork/mend-20261114/results/`.
- [ ] **Show vector Liquify while the stroke is still held (November 12).** Owner says the
  installed iPad only shows the reshaping after lift. The points should follow the gesture live.
  Preserve point-only vector deformation through the normal brush renderer, fixed exterior ink,
  and existing raster and linked in-between behavior. Trace the actual preview path and verify
  visible pixels before lift, after commit and after Undo, with a bounded work window. The live
  starvation fix now passes the focused on-screen gesture and its old-behavior fault check.
  Vector and raster Liquify passed 100 simulator checks. The combined release candidate
  `6c0b37e6` includes the In Place cancellation fix and passed both fast tiers. Installed in
  `8214421f`; physical Pencil confirmation is open.
  This builds on the shipped point-only vector rewrite: ordinary brush rendering retained,
  vector material transport removed, old packages repaired and owner-confirmed, and the
  temporary converter removed in installed ancestor `ec62d712`. Real-pencil confirmation
  remains the open owner workflow; preserve exact exterior, raster and linked behavior.
- [ ] **Find and fix the cause of recurring canvas freezes (November 12).** The iPad still reports
  freeze repairs and records flights. The watchdog is recovery. Compare recent flights with known
  healthy touch sequences and earlier false repair reports. Establish where touch ownership or
  recognizer lifetime goes wrong and fix that path. Owner reiterates that recovery is temporary.
  Verify the affected input works without replacement. Once the root fix makes recovery
  unnecessary, remove the superseded watchdog code, state, messages, tests and documentation
  cleanly. Preserve independent diagnostics. A repair notice alone does not prove a visible freeze. Owner says the
  failure is intermittent and difficult to reproduce. Use captured failures and raw touch binding
  as evidence, and avoid treating a short clean device run as resolution.
  November 13 at 00:14 Toronto: Kevin reports another canvas freeze caught by PaintApp.
  Retrieved repair #23, `flight-20261113-001333.jsonl`, 391086 bytes, in the existing
  freeze-flights folder. During a moving two-finger gesture UIKit canceled one contact and
  reissued it at the same location ~10 ms later. The replacement lacked pinch, rotation
  and stroke bindings. Both contacts traveled substantially. This is separate from the
  old timer's premature checks. The recorded transform label is cached at touch start and
  cannot prove that pan never moved. See `freeze-flights/readout-20261113-0014.md`.
  Kevin explicitly wants the freeze fixed from existing evidence if possible, otherwise
  the automatic recorder must gather decisive evidence without asking him to reproduce,
  start Record My Actions, save another flight, or run more manual tests. The existing
  synthetic gesture supports lift/restart as a control, but cannot generate UIKit cancellation.
  Use the same flight ring to capture applied transforms and handler delivery at bounded
  contact/episode edges. Prove the automatic trigger stores a moving partial reissue like
  #23, as well as the earlier missing-admission case, while healthy movement stays quiet.
  If current evidence supports a corrective input ownership change, test it with a replay
  of raw contact events and uninterrupted/ordinary recontact controls. Otherwise use the
  automatic capture to distinguish lost recognition from unchanged or unpublished motion.
  Keep instrumentation separate from the root fix and remove recovery after the fix is proven.
  Automatic recorder `8214421f` now saves both qualifying patterns and records real transform
  and delivery. Replay #23, actual healthy pinch, same-editor automatic save, and faults passed.
  App-source Debug/Release 5633 per tier and exact five compatibility checks passed.
  Installed and launched at 02:12 Toronto. Retrieve subsequent automatic evidence independently.
  Five retrieved flights record six repairs. One Nov 11 sequence loses all pan/pinch/rotation/ink
  bindings on the next three-finger gesture before UIKit resets mid-gesture. Reproduce the late
  third-finger sequence and trace that reset/ownership failure. A separate Nov 8 sequence proves
  a previous lift's watchdog can evaluate a newer gesture ~40 ms after raw cancellation and ~20 ms
  after window count zero. Candidate binds each check to its own last lift and passed simulator
  logic. Keep the recognizer reset root cause open.
  November 12 read-only refresh found no new flights. The bracketing sweeps show the same
  recorded recognizer identities. In the failure, pinch and rotation enter failed at lift,
  all four recognizers are absent on the next admission, and the stroke resets during that
  next gesture. The existing recorder does not expose live attachment and state at admission.
  See `~/PaintWork/crash-20261111/freeze-flights/refresh-20261112.md`. The installed automatic
  capture now handles this evidence request without a manual recording. No new automatic file
  was present on November 14.
  November 14 evening: the original detector requires missing navigation bindings.
  A moving pair with sound bindings and no applied navigation can escape a diagnostic
  save. Extend the existing automatic recorder only for that concrete evidence gap. Qualify
  real motion, intact admission and unchanged view across samples, and suppress intentional
  blocks and stationary/tap cases. Reuse existing samples and silent flight storage.
  A gesture root fix remains open until a captured failure identifies it.
  Exact `9b20cd04` passed 25 Debug checks. A cold healthy pinch moved and grew the visible ink,
  recording 24 real navigation writes and no false miss. In a separate simulator-only fault,
  both contacts kept all three bindings and UIKit reached changed, but the view stayed
  unchanged with zero writes. The app saved the automatic file before any manual save.
  The file records four qualifying samples and 40 pt of relative travel. Source restored.
  Device evidence and the gesture root cause remain open.
  See `~/PaintWork/bound-freeze-capture-evidence/`.
  Checked the potential hidden-layer dependency before changing gesture ownership. Cold
  simultaneous pan/pinch passed both visible and hidden on unchanged `ef335c4b` app code
  (`86a96b18` test), including the hidden-layer brush notice. The first probe's staggered
  gesture failed its visible premise. This result does not establish the cancellation/reissue cause.
  The earlier same-second filename collision was fixed in installed `45e067a5`. Both
  recorder actions append unique UUIDs through their shared filename helper, covered by
  FlightRecorderLogicTests. Repair #20 survives in overlapping flights from the old build.
- [ ] **Deferred: view previous crash reports in the app**, similarly to recordings. Owner asked
  “at some point if it is possible.” Keep deferred until requested.

Other outstanding requests remain below. Historical status/proof paths may refer to the PaintWork
folders the owner deleted during the emergency cleanup; verify availability before relying on them.

## Remaining work as of November 13

**November 16 evening.** Perspective Fit (`fecc1a8f`) is done and the assembled gate passed
(13/13 cold, 5,654 + 4 skips per fast tier). `main` is now the single tested line, synced to GitHub.
Installed on the iPad that evening (`fecc1a8f`). Owner to check: circle+line Mend Fill, Undo with
stream off and on, erasing speed, Liquify following the Pencil live.
Remaining: physical iPad confirmation of the items below, freeze/crash root causes, Windows SSH.

**November 15 continuation.** Device was paired but still locked. Continue the detailed audit
on the signed `01fb0fe7` lineage: independently reproduce the perspective resize corner case,
qualify old-writer package compatibility without touching the owner's library, and close the
settled Undo measurement gap using the existing device probe if it can isolate the visible
result. Verify actual source and test receipts before repeating runs. The source decision and
iPad readiness are still pending.

- Old saved Views can still hide a group's descendants when the project was last saved with
  the group visible. Exact `01fb0fe7` failed both nested-folder and member-layer reopen
  assertions after the artist reapplies the old View and shows the group. The old writer
  could produce this through Hide → Add View → All → Save. Repair each saved visibility
  state independently in the existing migration. Keep the current-format guard.
- A separate historical writer check shows an empty legacy compositor Input A below
  populated Input B, while dropping the slot tag ranks the empty folder above it. Covered
  fixtures populate both slots. Preserve the real order with a mixed old fixture before
  retiring that migration. The two previously recorded owner archive paths are absent;
  seven local candidate packages contain neither legacy marker.
- Legacy View fix `d5ff1463` passed 63 focused checks and the reverse fault. The cold
  Gallery proof passed with tracked older artwork, verifying its ink hides and returns. Container resize follows actual
  artwork through Move, Rotate, Repeat's stored pose and Shake in `ff0a5e94`, with 56 focused logic checks and the cold Resize gesture green. Fractional
  projective Parallax remains separate: a known Fit yields no half-share pose when the
  old blend's origin falls on the mapped vanishing line. On November 15 the owner answered
  “no scenes need to be preserved” to the A/B appearance choice. Implement Fit-safe placement
  in the shared Parallax math. Existing scene packages remain intact; an older saved scene can
  render this transform differently. Use the authored rest box, with no compatibility flag,
  new persisted state or general interpolation overhaul. Parked clean on
  `tmp/nov15-parallax-fit` at `2907dc4b`. Implement and verify the 400×200 placement and
  600×200 vanishing-line cases, then run the final assembled gates. The superseded assembled
  gate was cancelled and supplies no pass credit.
- Settled Undo `7b27c469` traces from the press through restoration to assignment of the
  exact matching committed base. The real recorder UI produced both a deferred nonempty
  and immediate empty assignment on one cel. The unattended Probe recorded two deferred
  assignments. Physical comparative timing remains open.

Kevin reiterated that a blocked release must not stop the other open work. Run independent tasks
in parallel and keep the exact simulator-qualified iPad candidate isolated until signing.

- [ ] **Reconcile the tested installed source with the canonical repository.** The qualified
  device build descends from the installed code, and canonical local main has separate recent
  records. Establish a clean integration plan from exact ancestry and an actual change inventory.
  Preserve the owner's queue, qualified source, remote state and all unqualified branches.
  The November 14 comparison at `afd2030c` finds canonical local changes in four policy/queue
  documents and 473 changed paths across 656 commits on the current candidate. A three-way
  preview conflicts in AGENTS, HANDOFF and TODO; no app-source conflict is involved. Keep the
  installed lineage available in its own branch. A transfer that retains both branch histories
  in main would require the repository's prohibited merge commit. A single-parent import on
  canonical local main would leave the iPad renewer unable to choose between the two source
  histories. A linear continuation of the tested release with the canonical document content
  replayed keeps the iPad lineage and fast-forwards the current remote, while preserving
  canonical local commits on `tmp/nov14-canonical-before-promotion`. Prepared local review
  branch `tmp/nov14-promotion-review` at `646402f8` with identical production tree to signed
  `00cb237b`, two verified test owners and reconciled documents. Both Git ancestry checks passed.
  The evening review `ee98a190` carries the same queue onto exact code `01fb0fe7` and retains
  the detailed audit. App and UI test trees match the candidate. The new preview still
  conflicts only in records (HANDOFF and TODO). The local-main migration decision remains
  open; submitted the owner choice on the verified branch and named Desktop backup. Remote
  refs and renewer files were left alone.
  Ref and conflict receipt:
  `~/PaintWork/nov14-audit-evidence/integration/`.


- [ ] **Bound stream timing measurement storage between displayed pictures.** In the current
  stream coordinator a tick may decode or update off-frame content without presenting a
  picture. The timing array accumulates every tick until it next presents, and the summary
  then walks the array. Retain only count, total duration and maximum in the existing
  measurement owner. Preserve its presentation cadence and log/marker output. This is
  bounded telemetry, separate from finding a device restart cause. Exact `3c939109` passed
  26 Debug checks including visible On Top stream placement. Extracted production behavior
  and existing assertion expressions distinguish lost count, sum and peak. The native
  peak fault failed as expected, then passed restored. Assembled `01fb0fe7` passed both
  fast tiers and all 19 targeted UI checks. Release and shared-source promotion remain open.

- [ ] **Reconcile the remaining on-screen rendering and brush audit controls.** On signed
  `00cb237b`, drive the existing masking, playback bake, live/linked Liquify, brush curve
  drag, and brush preview restoration tests. Compare visible pixels and selection outcomes
  with the audit's earlier component results. If a check fails, identify the actual product
  or fixture cause before editing. Keep physical pressure and startup evidence separate.
  Exact `00cb237b` failed the held-stroke assertion in Colour Mask. This test stops on
  first failure, so its later stroke-admission and final drawn checks were not reached.
  Inspect the timed sample and failure recording to distinguish delayed mask preview from
  screenshot/fixture conditions. Video shows the ordinary moving stroke clipped by red,
  then the blue paint outside the mask when Shape Hold displays its editable straight
  line. Run ordinary continuously moving Brush as a separate control, without removing
  its sampled on-screen/pixel assertions. Verify the editable shape's paint respects
  the same existing layer mask while its handles stay accessible; inspect the spec and
  reuse the layer's mask owner before choosing a fix. Evening batch finished 12/13:
  playback/bake, brush-curve, all four live/linked Liquify checks and the other three mask
  workflows passed. The ordinary Brush control on unchanged app source `3992374b` passed:
  during motion it covered the outside probe while only paint inside the mask was visible,
  then committed one correctly clipped stroke. The Shape Hold draft takes over the visible ink
  and had lost that mask. Candidate `31e66383` passes the exact admitted clip to the draft's
  paint host and keeps its guide and handles independent. All 53 focused checks passed,
  including the new cold draft through commit, a subsequent unmasked shape, and unmasked
  live corner drag. Inspected clipped paint with the exterior guide and endpoint visible.
  Suppressing the clip red-lined the outside-preview pixel, and retaining it at teardown
  red-lined the next unmasked shape. Restored green and an inspected 1080×810 pt landscape
  witness both passed. The exact production SHA remains `31e66383`.
  Combined `01fb0fe7` passed all 19 visible workflows. That includes brush preview restoration,
  the opacity control, the recorded Mend Gaps motion and open-lasso Move. Inspected the same
  run's clipped draft, solid red fill with its reference hidden, and settled Undo with the
  earlier stroke over a green stream. Debug and Release each passed 5,647 plus four opt-in
  skips with all static IDs reconciled. Arm64 Release `01fb0fe7` is signed and verified.
  The iPad was still passcode-locked at 19:02, so installation and physical use remain open.

1. **iPad update and real use.** Signed Release `8214421f` installed and normal-launched at
   02:12 Toronto November 13, with a profile through November 20. It includes live Liquify,
   Mend, stream/Fill/Undo fixes, resize, recording, bounded graph preview and new automatic
   freeze evidence. App-source fast Debug/Release each passed 5633, plus targeted cold and
   exact compatibility checks. Compare rapid editing with a moving stream and with it off.
   Physical crash and settled Undo latency verification remain open. The later open-lasso
   Move change is qualified at `ef335c4b` and awaits the next deployment.
2. **Canvas freezes.** The candidate fixes the recovery timer and preserves recordings of
   close-together repairs. Capture or reproduce the separate recognizer reset failure and
   fix it before removing the recovery code.
3. **Older iPad behavior.** The installed Release includes editable vector Copy/Paste,
   Copy to the left of Duplicate, small Move boxes, Set Down display continuity and stream
   position, Undo thumbnails, Mend All Fills, and newest-version backup retention. Existing
   simulator checks cover those mechanisms. Both clipboard menus passed cold, including
   widened pasted ink and width Undo. Confirm the one-tap Move report in Test and verify
   remaining physical workflows on real scenes, including saving and recovery.
   The October recording is no longer on the Mac or in iPad Recordings. Preserved Git
   evidence shows the lift began and then canceled on all three taps. The image-ownership
   fix is installed and prior cold one-tap evidence survived. The actual Test scene remains
   unverified. On a saved scene, tap Move once after lassoing visible vector ink. Verify
   the untouched box stays up, then use one Undo to cancel the zero-nudge lift before
   reopening Settings. Use a disposable copy for a drag or Set Down.
4. **Architecture and performance audit.** Close the remaining concrete rendering, input, media,
   and saved-data issues and test their existing implementations. Keep development storage bounded.
   The exact `01fb0fe7` opt-in Release run passed both Fill checks and isolated Lens Blur.
   The interactive fixture verified exterior safety and cut-out coverage. Mend All repaired
   the 300- and 1,000-cel fixtures and verified atomic refusal. Lens Blur returned a changed
   2048×1024 picture with a radius-zero identity and Gaussian comparison. Timings and footprint
   apply to these simulator fixtures. Evidence: `~/PaintWork/nov14-evening-evidence/`.
   The full audit and follow-through checklist is in the audit sections of this file below.
5. **Windows streaming.** Verify Blender, source switching, reconnects, clipboard, bake and latency
   on the real link. November 14 Tailscale sees the laptop online and SSH responds, but it
   still rejects the configured key. Desktop Commander lists the laptop offline. A read-only discovery
   packet on Tailscale got no reply. The stream service's TCP accept can replace an active
   iPad, so leave that probe to the real desktop session with Kevin. Avoid test hosts that
   prompt repeatedly for firewall access.
6. **Deferred.** In-app crash history, interpolation redesign, multi-cel selection, linear-light
   blending and audio/video editing. Brush preset importers remain dropped.

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

**Session 49 (2026-10-14):** the owner asked to continue through every actionable item, stopping only
for genuinely required input or context degradation. Agent count is unrestricted for now; usage
conservation and output quality take priority over speed. Use focused delegation and cheaper models
for routine work, with occasional queue reports. The owner asked to work independently while asleep
until 10 a.m. Toronto time. Raster scope and fixed exterior pixels for vector selections are ruled below.

**Checkpoint 2026-10-23:** three active asks below remain unfinished. Point-only Liquify and newest
backup retention are integrated on an unmerged branch; repair 75/75 and runtime 302/302 are green,
but combined 303, runtime 13mutants, fast tiers and current UI remain unqualified. Test1 erasing has
memory evidence but no proven cause or fix. Previous normal Release bcd7a6af remains the installed
build; no physical device operation occurred this pass. See HANDOFF for the current native owner.

## New audit findings — recorded October 29 before implementation

- [ ] Resolve the valid fractional-projective Parallax resize blocker before qualifying52424454.
  Independent review proves Fit100²→400×200, share0.5, perspective quad gives a point~20pt too far
  right. Existing added Parallax test used share1/pure translation and misses it. Add a drawn finite
  regression; inspect existing blend's global projective factorization. Do not add persistent resize
  basis/per-framebaking or silently change unresized artwork/interpolation behavior. Prepare A/B
  pictures before any appearance choice; future interpolation overhaul remains deferred.
- [ ] Audit/retire real inline saved-format migrations (known compositor slot and pre-group-property
  marker) through the required one-shot package repair/current-library gate. Preserve old-writer
  packages and Projects/Backups/Trash/order; remove corresponding decoder branches/flags only once
  migrated and confirmed. This is separate from strict current-node payload validation, whose17
  actual historical encoders always emitted required op/Mix mode. No new permissive decoder route.

The combined409 native baseline remains frozen atd798 in the integration worktree. This records-only
branch is the live queue so new root-cause work can proceed independently; merge these records back
only after the native/source extraction boundary. None of these findings is physical crash proof.

### Current evidence and decisions

- **Eraser/brush source assembly:** root reviewed the fragment-bounds source and bounded tiny-dab
  transition. Whole BrushEngine67 passed with source731 exact. Their five production/test paths
  are assembled for a combined native baseline; no diagnostic sentinel/temporary cost method was
  harvested. Fragment bounds124, mutation controls, public1pt and matched cost still remain. The
  arrival-union control is sensitivity-unproven and unknown-fragment defense has no fixture credit.

- **Picture component assembly:** f422 public Paste/Multiply/Bake/save/reopen passed1/1; root
  verified source731 and inspected all three owner-landscape captures. The six-cell arrangement
  stays correct. Its five source/test paths are now assembled into the integration candidate;
  whole68, mapped controls and final combined checks still remain. No install or main merge.

- **Assembly efficiency:** root has source-reviewed and assembled the small Shape scale and export
  frame-range corrections into the integration candidate before their native checks. Their original
  pins and control proposals stay frozen. This is unqualified source assembly, not completion, main
  merge or install; the next combined slice must repin its classes, counts and controls.

- **Current checks:** HUD teardown is integrated after its release/menu checks and old-code control.
  Tiny-brush direct-area8a5 finished65/66; only its actual-gradient handoff failed. The calibrated
  coordinate sentinel passed. Fresh7a400 transition candidate has whole67 and matched-cost proposals
  prepared; none of its source is integrated. PNG/Bake64 logic and old3 public tests passed, while
  the new public test stopped on optional Move premises. Simplifiedf422 is now running the actual
  Paste/Bake/save/reopen workflow with unchanged pixel checks. Eraser A2 Release passed1 and counted
  27full4096²pictures plus6reduced480²pictures across36cuts. The fresh-fragment bounds candidate
  reuses the existing geometry walk/map; focused124 is pending. No physical crash cause is proved.

- **Old generated-file cleanup:** the single-log compression trial passed byte/metadata checks.
  The26-path derived-PNG trial preserved bytes and permissions but failed its original exact-xattr
  oracle because macOS updated `com.apple.provenance`. Keep that result failed. Root permits a new
  narrow revalidation accepting only the exact recorded old/new OS-managed token on these old
  nonexecutable derived PNGs, never manual security-xattr writes. Original parent-directory times
  were not durably saved: record this limit, never invent restoration. Before more mutations,
  journal timestamps durably and restore them in finally. Root reviewed helper98a2d853 and
  the independent all1085-group validation; the exact fixed three-folder derived-PNG batch is
  approved under its matching external grant, with full byte/metadata checks, durable directory
  restoration and measured free-space change. No DSC mutation is approved. Timing waits for IO join.
  Protected artist packages, original recordings, current54/55 evidence and Products stay untouched.

- **Generated-build resource audit:** recorded Release builds compile the UI tests for both
  arm64 and x86_64, while the owned iPad simulator executes arm64. Select only the active
  architecture for the Release UI-test target; retain the shipping app target's existing settings.
  Verify actual arm64 build and unchanged test counts in the final Release gate. This is a test
  resource correction, not an app performance claim.

- **Shape handles during a tiny pinch:** source review found that ShapeOverlayView skips update
  side effects for nonpositive canvas scale but still stores it; several handle/chrome dimensions
  divide by that value. Reuse the consistent scale guard already used by the sibling object overlay,
  then check finite hit/chrome geometry and public shape manipulation. No crash attribution.

- **Photo-import feedback audit:** `AddMenu.primePhoto` silently discarded transfer/decode/priming
  failure while the adjacent video path reports it. Reuse the existing menu notice for photo
  failure; no new state or import abstraction. Existing Add-menu checks and assembled gates remain.

- **Picture saving audit:** an actual save/reload showed a scale2 placed picture doubling in drawn
  size. Its PNG keeps rotation but reloads at scale1; the placement needs correct image-unit
  conversion. Fix and package round-trip checks are pending; no new saved format is proposed.
- **Missing new ink:** the exact saved red stroke also disappears in an independent full render,
  so the investigation now targets shared small-brush rendering rather than only preview handoff.

- **Architecture/performance audit:** the optional performance readout can leave its frame counter
  running after returning to Gallery. Its display link retains its monitor, so monitor-deinit
  cleanup is unreachable. Teardown now belongs to the existing HUD owner; release/public checks and the old-code
  control passed their intended outcomes. The correction is integrated; final combined gates
  remain. No crash-cause claim.

- **Bake audit:** a pasted picture could lose its rotation when baked. OLD drawn-pixel reproduction
  failed as expected; the one-line orientation-preserving candidate passed25 logic checks. Public
  UI1 stopped on an unanswered iOS Paste prompt before Bake; a test-only prompt correction, controls
  and assembled qualification remain. This is part of the architecture/effects audit.
- **Recovery gate:** the fresh strict-text run stopped at its new red-ink drawing premise before
  Cancel/Restore. Its exact saved1pt stroke reproduced missing ink independently; the shared-dab
  candidate now renders it and passed its strict dedicated saved-stroke method. Keep that regression.
  The recovery test itself needs a reliably opaque larger mark and the existing measured slider
  helper, because native low-position adjustment produced1pt instead of the requested size. Preserve
  the red-core assertion, then restage a fresh simulator for actual Cancel/Versions/Restore/Trash
  proof; no recovery pass is claimed yet.

- **Crash and lag:** Test1 is4096²; Kevin confirms rapid To Cross erasing triggers the failure. The
  crash cause remains unproved. The simulator Test1 capture made36 cuts and produced25 full4096²
  picture outputs; immediate dark ink became Recolour red at rest, so no persistent Recolour loss was
  found. The separate740 candidate replaces repeated per-sample full-base work with the admitted
  native window on ordinary single-cel To Cross. It passed whole112, four mapped direct assertion
  controls, and a clean normal35 rebuild; root inspected white paper, all three removed lines, Undo,
  and effect-pan images. These are simulator component results, not a physical crash diagnosis or
  final Release/performance qualification. Preserve the Test1 input/flight and obtain fresh owner
  readiness before another device workflow.
- **Move and stream:** only repeated-tap Move was reported as specific to Test. Stream displacement
  occurs after release or Set Down. For the brief Move-exit gap, Kevin explicitly prefers the
  existing lifted drawing remain visible until the compositor's finished picture is shown.
  Current corrections reuse those owners; no timeout or parallel Move cache was added.
- **Text/menu:** source and two flights tied false repair notices to the canvas recognizer accepting
  live text-view touches. Existing touch ownership now excludes it at touch-down; no timer/state
  added. Whole owner/text34 passed before/after deliberate controls and inspected red-word/menu
  pictures. Portrait menu continuity1+whole8 passed. Owner-landscape1 stopped at the next-pan
  assertion with Lens Blur settings visible over the canvas; inspect fixture occlusion first.
- **Saved files:** synthesized MotionGroup decoding removed its custom defaults. One typed array
  helper preserves omitted/empty registries while rejecting explicit null. Real previous-writer
  load/save/reload and whole30 passed; six null assertions failed under the old helper; temporary
  witness/staged copy removed; final whole29 passed. No null files in the250-package inventory and
  no current writer emits null, so no new repair/schema is justified.
- **Performance:** three opt-in Mend/Liquify cost tests are now harvested but **not compiled or run**.
  The300/1000-cel Mend All fixture is light synthetic72² data, not dense artwork. The actual
  copy-only week-of-saving APFS measurement is already qualified; do not repeat or extrapolate it
  into a physical300–1000-cel claim. Exact metrics/pins live in HANDOFF and evidence packets.
- **macOS prompts:** Kevin sees requests for ChatGPT access to OneDrive/other app data. Cause is
  unproved. Scope work to explicit repository, PaintWork and owned-simulator paths; do not scan cloud
  folders or change privacy settings.
- **Artwork/readiness:** original library exports, fresh Test export, recordings and copied Test1
  are hashed/protected. Earlier saved/unlocked readiness was consumed exporting Test; obtain fresh
  readiness before a further device restart. Automatic renewal must preserve installed6fb while
  main is older and advance its source/artifact/profile state only after a successful install.

**Mode3 source follow-up:** the740 candidate reuses the existing replacement window, CelContentPicture,
and UnlandedInk for ordinary single-cel To Cross. Per-sample cut resolution, one-gesture Undo,
captured references/poses, and refusal fallback remain. Four mapped controls reached their intended
assertions and the restored source rebuilt cleanly for normal35; whole112 and normal35 are component
checks only. No parallel cache/service/timer/state was added. Universal multi-layer erasing remains on
its existing route. Measure final Release work before claiming a latency benefit; no simulator result
establishes the crash cause.

**Current assembled-build boundary:** d30a's normal146 stopped at145pass/1fail because a pan crossed
the still-open Duplicate/Bake layer-options popup; the corrected740 fixture closed that popup through
its public control and the whole112 slice passed. The earlier7cc compile failure was a CGRect/CGPath
mistake in the benchmark fixture, later corrected. Release copied-Test1 capture1 passed with36 cuts and25
full picture landings; its timings do not prove owner-device performance or crash cause.

**Composed d30a result:** the earlier normal146 was145pass/1fail/0skip with exact source731. Its only
failure was the obstructed effect-bar pan; the corrected740 fixture closes the Duplicate/Bake popup.
The740 whole112 passed and raw/normalized image review confirmed white paper after all three cuts and
restored lines after Undo; the apparent black view came from image metadata/display. The full-screen
and element-pixel evidence has been reconciled. Keep the old packet immutable; no product visual fix or
crash cause was established.

**Latest validation:** candidate740e whole112 passed112/112 with0 skips; all four reviewed controls
reached their mapped assertion failures; then a clean Debug normal35 passed35/35 with0 skips. Root
inspected white paper after cuts, Undo restoration and effect-pan crops. Candidate files are now
harvested into integration in separate source, cleanup and screenshot commits. Static integration census
is731 source entries, fast5448/full6062; identifier/helper checks pass. The assembled integration has
not been compiled or run. Final Release, full fast/UI, performance and device gates remain open.

### Work queue

1. Finish copied-Test1 Mode3 diagnosis and review the existing shared-window presentation seam.
   Do not attribute the crash or claim an iPad speedup from simulator observations.
2. Complete remaining colour/effect/mask/graph/recovery workflows and actual drawn/owner-size
   evidence. A fixture setup failure proves no product outcome; preserve original results.
3. Finish genuine architecture/file-review gaps and remaining source findings through existing
   owners. Keep coherent compiler-isolation candidates out until their whole boundary is reviewed.
4. Qualify the exact assembled source: static/lint/project checks, complete fast tier in Debug and
   Release, affected UI classes, required deliberate controls, and the full phase gate. Count actual
   methods; Mode3 and opt-in cost witnesses bring static full count6062, fast5448.
5. Run paired Release fill/effect and current Mend/Liquify measurements with correct output and
   honest memory limits. Never call counted cache bytes whole process/device memory.
6. Complete Windows gates once its external state changes; no repeated unreachable-host polling.
7. Drive existing playback, grey-area pan, Move/graph drag-release and strokes; verify Release
   signature/profile/library protection; install qualified source after fresh device readiness.
   Confirm the recorded drawing, erasing, Move and stream behaviors on that build.
8. Remove each completed item whole only in the qualified main merge; push and update HANDOFF.
   Preserve original evidence/pins and name anything that could not be run.

Deferred interpolation overhaul, multi-cel selection, linear-light blending, audio/video editing and
other explicitly later features stay written down. Dropped brush importers are not reopened.
Detailed task sections below remain unchanged. Technical authority: HANDOFF.md and
`~/PaintWork/s54-final-qualification/root-next-gates.json`.

<!-- Status-preamble compaction only. Original bytes retained at ~/PaintWork/s55-recorded-regressions/status-preamble-compaction-17c00484/TODO-before.md and in Git. No task was closed. -->

## Bound curve flattening before integer conversion — 2026-10-26

The audit found that StrokeGeometry.flatteningSteps converts an unbounded control-polygon length
before applying its documented64-chord cap. A finite current-format curved fill can carry controls
above Int range; actual fill posing/Liquify mapping flattens before its later region/map checks.
Source finding62b0df17 is corrected8272 and harvested8682859f: the existing bound moves before
conversion, preserving ordinary rounding and coordinates. Current-format archive/reopen/nonlinear
consumer and whole94 passed;6 safe owner controls qualify7 new canonical application statements.
No unsafe old cast, new schema/parallel validator or Test1 attribution.

- [x] Finite current-writer/read witness, existing-owner correction, ordinary/capped consumer tests
      and6 safe controls are component-qualified/root-reviewed. Retain whole item until merged.
- [ ] Final assembled Debug/Release and cold drawn gates; review any newly reached downstream
      arithmetic separately, without claiming global bounds.

---

## Protect library relocation and Trash backup ownership — 2026-10-24

Implemented and included in normal847/847/base49 qualification, unmerged. Strict shared file-tree
and content comparison replaces equal-count/bytes identity; Trash purge uses project UUID ownership.
Comparison/read/link/ambiguous ownership failures preserve original artwork and history. The direct
linked-entry assertion is retained; a later unrelated filesystem rejection cannot prove this policy.

- [ ] Qualify final integrated fast/UI gates, graph/lints and source restoration before merge.
- [ ] Keep real packages/backups protected; no backup retention policy change is part of this correction.

---

## Background lifecycle ownership fixes — 2026-10-24

Implemented in the same qualified dependency: export cancellation fences old completions, startup
stage cleanup uses the existing package serializer, and document close cancels bounded batches of
eight thumbnail backfills. A synchronous batch may finish if close is triggered reentrantly. Source
review found no concrete remaining defect; final-source fast/UI/device gates are still pending.

- [ ] Preserve cancellation/refusal and exact-source proof in final qualification; do not claim older
      component results cover new integrated code automatically.

---

## Repository-wide architecture, cleanliness and performance audit — 2026-10-24

**Active, source consolidated; final qualification and file-review gaps remain.** Owner asks for a
thorough audit: “codebase cleanliness and good architecture as well as performance is a priority”,
“refactor things that are messy and also find and fix bugs”, “Zombie code or bloat … should be dealt
with. Dont be afraid to prune.” Trace actual consumers before changing them; reuse one existing owner
or seam, remove superseded paths whole, and measure claims. Real scenes contain300–1000 drawn cels:
design around a window/byte budget, never load it all. Deferred features stay deferred.
Kevin reiterates October26 that fixes must address root causes and preserve good architecture;
remove superseded owners/paths instead of stacking workarounds. Independent review and actual
regression evidence support bounded confidence, not a claim that every fix is certainly correct.

The18 current finding headings and file-level gaps are in docs/ARCHITECTURE_AUDIT.md; the old19
index also counted the now-retired temporary converter. Current statuses replace historical pending notes.
Inventory-only files are not reviewed code. New source is not called complete because it is committed.

- [ ] Data protection/background: finish final-source gates for strict migration/Trash ownership,
      export cancellation, serialized cleanup and close-owned thumbnails; retain the qualified controls.
- [ ] Triage current compiler warnings by ownership: distinguish pure-value isolation mismatches,
      real background actor access, missing awaits and deliberately synchronous media reads. Actual
      Video normal11 log has259 warning occurrences,182 distinct location/message rows; not182bugs.
      Do not silence warnings with blanket unsafe annotations or change scheduling without tracing
      callers. Unused locals may be pruned after confirming their initializer has no required effect.
      Source/independent review accepts a bounded first patch: only existing package serializer
      queue/key/functions, lock-owned RasterStorage/RasterResidency and pure/locked CompositorBudget
      get explicit nonisolated boundaries; remove the unused PoseBake startFrame and estimate-only
      Onion canvasMP declarations whole. No bodies, locks, scheduling, protocols or policies change.
      Root reviewed core6 patchbb437dce before implementation. Its Debug app+UITests build succeeded
      with0 tests, exposing candidate-interface warnings. The three-prefix successor07a was
      interrupted on new cache/factory warnings (operator cancellation, not completed compiler
      failure). Both annotation candidates stay UNHARVESTED: the coherent pixel/primitive boundary
      is larger and no runtime defect is proved. Keep the source triage; the two dead-local
      deletions are harvested alone ate88a25ab. Finish drawn-workflow gates before considering a wider isolation migration.
      No automatic cascade, blanket namespace opt-out, new locks or actor hops.
- [ ] Bake recovery/close: existing baker/store/read demands share one authoritative source and checked
      admission; corrupt/missing/zero-byte derived files recover without permanent retry. Keep final
      headroom refusal and actual unlink failure coverage. Derived cache bytes are separate from source pixels.
- [ ] Mask budgets/video/vector undo: included in normal847. Mask planning prices transitive indivisible
      closure and retained mix slots; minimum-one-row exception stays explicit. One MaskResolver checks
      metadata cache before dependency pixels. Refusal never becomes an unmasked stroke; onion refusal
      cancels/hides stale frame/clip. Video reads use per-manager closeable clients, pressure trims ring
      and reader LRU, late work cannot land after close. Two held native samples/reader and private
      AVFoundation allocations remain separate from copied ring bytes. Vector costs count actual
      retained payload identity without copying/unpacking or persistent pointer caches; saturated costs
      propagate through existing UndoBudget/history. Preserve the qualified52-target ledger; finish final consumer UI/gates.
- [ ] Editable raster: one app-wide RasterResidency charges provider-owned source allocations and
      configured working/checkpoint reservations; native image aliases and unresolved snapshot leases
      keep their real charge. Explicit COW admits before mutation. Immutable version/backing handles
      serve raster/baked tiers, frozen recipes, undo and save; current-document compressed protection
      and dirty checkpoints use existing ProjectStore clone/PNG serializer, with owned stale-temp cleanup.
      No schema, backup-policy, parallel writer/cache,1000FD or eager all-cel hydrate. Staged affected
      cels preserve Liquify→fill→shape→text order, queued text, masks and drafts on later refusal.
      Planned-frame stroke tuple settles before recording then begins after playback/before spawn;
      patch/whole-cel undo preflight distinguishes admitted blank from failed reads and drops pins.
      Resize/flip prepare all outputs serially before fenced atomic install. Owner UUID+version keys
      include interpolation references; frozen snapshots reuse original owners. Tag04 changes only
      disposable .pbk digests. Original32 methods and5 finite-pass additions pass within normal430;
      qualified raster faults and the original broad-control limits are recorded in the current ledger.
      Full fast/cold drawn UI/landscape and remaining assertion gates remain. Counted ownership is not whole RSS,
      private ImageIO, derived compositor memory, placed-image/video ownership or Test1 causation.
- [ ] Stream: one completion-paced writer/run, bounded producer payloads,64MiB frame/256KiB chunk checks,
      old-connection callback fencing/join and error/stop settlement replace unbounded ownership.
      Final7c C#166 normal methods pass both configurations;16 assertion targets/15 recipes and4
      arrangement controls qualify, with63 source/fixture entries exact. Swift76 and the callback
      completion correction passed within normal1cf422/422, zero skips; final35 stream/fit/walk
      controls qualify at their selected mapped assertions; remaining assertion gaps and final-source/UI
      gates stay pending. Windows fake transcripts return synchronized snapshots. Real-link stage5 remains owner-waiting; no deploy.
- [ ] **Qualify bounded Windows discovery on the real host.** Current integrated
  `526312a3` already rejects DNS names beyond 255 expanded octets or a 63-octet label
  before allocation, preserving valid compression and QU. Exact production blobs
  match the earlier isolated DNS/clipboard fixes. Git records prior targeted failure
  controls and a later 188/188-per-tier isolated Windows run; the old raw TRX is not
  available. Finish exact Debug/Release, the deliberate refusal controls and the real
  streaming link on Windows. No native SDK or WPF host exists on this Mac.
- [ ] Brush/editor: bounded8MiB actual-image preview LRU and keyed row result replace unbounded/unkeyed
      retention. Final823e proof distinguishes exact2 vs2.25 scale within one old rounded bucket and
      checks actual requested600×120 pixels. Shared PaletteColor rejects malformed persisted hex rather
      than silently displaying black; normal strings are byte-preserved. Brush/palette logic passed within normal1cf422. Cold A→B→A drawn row and typed-colour
      recovery methods individually passed/LOOKed in676 (whole73 was67pass/5fail/1skip). First29/gap8 fault qualification covers all53
      selected brush/palette/metadata/curve assertions. Final-source whole UI classes remain pending.
- [ ] Curve editor drag: sourcecf184033 is integrated. Existing moving returns the authoritative
      landed frame with the updated curve, so clamped continuation cannot freeze or retarget a neighbor.
      Two logic and one drawn landscape UI method added; the selected logic/fault assertions qualify
      in the first29/gap8 ledger. Final full UI class still must preserve brush response/channel behavior.
- [ ] Stroke path/heading: exact redundant stationary chord-scan bypass and LiveWalk prefix draining
      retain all samples/channels and floating-point timing order. Naive coalescing was refuted by a1ULP
      counterexample; O(N) input storage remains. Qualify new controls/faults/drawn parity and measure
      any performance claim. No interpolation overhaul is authorized.
- [ ] Test hooks/obsolete runner: destructive reset/corruption seeding is simulator-only even in Release;
      use direct existing platform fact, no policy wrapper. Verified unused parallel_test.sh removed.
      Ordinary simulator UI/device compile and final static gates remain pending.
- [ ] Newly traced Mode1 eraser handoff: preserve the already-minted gesture seed through existing
      VectorCanvas.erase/hybrid punch and universal commit. Actual pixel/undo/archive qualify at260/seed5; new coldMode1 source59a3 is harvested,
      public runtime/wholepictures pending. Do not attribute the owner's Mode3 respring to this independent issue.
- [ ] Finish text final combined checks. Full UTF-16 style restoration is integrated;31 actual-view
      checks and two reverse faults qualified earlier. The cold public Select All/colour route now
      passes with a grip-clear fixture. Touch-down ownership fixfccc06db removes false repair notices
      without timers/state; wholeowner29+Text5 passed before/after two controls (three direct targets),
      with native menu and both red words inspected. Actual induced stranded-repair recovery is not
      claimed; landscape menu-continuity fixture remains separate.
- [ ] Resolve actual current graph gesture delivery and landscape menu continuity without
      weakening product oracles, then fresh whole-class runs and whole owner pictures.
- [ ] Graph/capacity: shared resolved-destination/net-child admission is integrated at8e80; actual155
      normal and original42 deliberately broken contracts qualify. Capacity24follow-on qualifies all41 further contracts; public cold6ef
      remains open and four further outcome limits stay recorded. Keep proper-descendant semantics and
      one resolver; no renderer truncation, fake IDs, duplicate state or new rollback service.
- [ ] Effects numeric domains are component-qualified:5a63/63+13safecontrols, ec50CRT116/116+
      13safecontrols; exact root harvests retain original CPU/oracles/tolerances/global flags. Curve
      narrowing8272 passed94/94+6safecontrols and is harvested868. Final assembled Release/cold UI/
      paired output-verified cost remain; no unsafe old cast or Test1-cause claim.
- [ ] Finish file-level/independent review, new affected zero-skip baseline, actual assertion mutants,
      exact final fast Debug/Release, lints/PBX/graph, cold workflows/pictures and paired performance.
      Then fresh owner save/unlock/export, signed clean Release/device checks and actual eraser cause.
      Owner now permits review installs at agent discretion; preservation/signing/actualdevice gates remain.

---

## How to read and keep this file

Every item is a **status**, a short **description** a future session can pick up cold, and **what is
left** as a checklist. Items are in **queue order** — the top of the list is what to do next.

**An item leaves this file when it is merged, not when a branch exists**, and it leaves *whole* rather
than being marked done: `git log` and the spec documents are the history. The owner, 2026-09-06:
*"Basically I want to be able to read the tasks on TODO clearly without already finished tasks."*

**Three in flight at once** unless the extras need no simulator — the cap is about the machine, not the
plan (`tools/simlock.sh`).

**Before adding an item, check whether an existing one already covers it in different words.** A
restatement filed as a new item is how one feature came to be specified in six documents at three
scopes before a line of it was written. This file has since carried two live duplicates for weeks.

**Record an ask in the owner's own words, and fold a ruling into the item it rules on.** A quote is
cheaper to keep than a decision is to rebuild. But an item reads as *one current description*, not as
the transcript of the argument that produced it — what happened this pass belongs in
[HANDOFF.md](HANDOFF.md) and in `git log`.

**Cite a symbol, not a line number.** A 2026-09-06 audit found ~10 of one item's 15 `FILE:LINE`
citations and 5 of another's 11 no longer resolved — every named fact still true, every anchor wrong,
two of them because a file moved directory. A symbol name survives a refactor and a line does not.

**A bare item number in a spec or a code comment may name an item that has already left this file.**
That is the merge rule working, not a dangling reference: `git log` and the spec documents are where a
completed number resolves. Two are cited often enough to name here — **(10a)**, the Oklab colour ramps,
and **(38)**, the graph editor's bezier tangent handles and their tap grammar. Do not re-add a finished
item to this file to make a citation resolve.

**Verify a status before trusting it, including this file's own.** That same audit found fourteen
assertions here that the code contradicted — features called unbuilt that shipped weeks ago, a blocker
called live that had lifted, and two commit shas that are not on `main`.

**Old files are repaired once, never read forever.** The owner, 2026-10-10, retiring the earlier "no
document has to survive" permission now that real scenes live in the app: *"I will still keep the rule of
no legacy code. If an update causes existing files to be outdated, then they should be automatically
repaired by a throwaway script the session makes."* So a format change ships with a **one-shot repair**
that rewrites the owner's existing files (Projects, Backups, Trash) to the new format at launch, and the
app's decoder knows only the current format. The repair is deleted, whole, once the owner confirms
their files are repaired. Build `2974b33` broke this rule and lost the owner's keys (TODO (153)).

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure taken before 2026-08-17 was at 4096², eight times the pixels.

---

## (27) Stream the computer's screen as a layer

**Status** — briefed 2026-09-13, designed the same day ([STREAM.md](docs/STREAM.md)), and **built through
stage 4 the same day**: the Windows streamer (`streamer/`, installed on the laptop as the `PaintStreamer`
task), the iPad stream layer, the bar with Freeze / Bake Frame, files both ways. On the owner's iPad.
What remains is stage 5 — proving it on the real link with the owner at the laptop — and the one
device figure §5.3 asks for.

**The owner's brief, 2026-09-13, verbatim in the numbered points:**

1. *"The purpose of this feature is to be able to stream my windows computer's screen as a layer live
   on the app. The example use case is that the user will open up blender on their computer, then
   rotoscope a character, move the camera around in the computer, then continue rotoscoping, etc."*
2. *"This feature will require another app that is to be installed on my windows laptop which will
   stream the video to the Ipad."*
3. *"The windows app should also have a drop box for videos or images which when they are pasted into
   or uploaded, will appear on the app via the import video or image feature. If it is also possible,
   make the ipad app able to export to the windows app and save to the laptop."*
4. *"In the app, the stream tool should be under actions, and like a video it makes its own layer with
   the stream object inside of it."*
5. *"When the user is actively on the layer, there should be an options bar (the same kind as move or
   lasso tool), and in it should be the option to freeze the stream, or to bake the current frame. When
   the user presses bake to frame, the current frame in the layer is split as a new cel, and in that
   cel will be an image of the screen when it was baked. For example there are 4 frames and the stream
   layer has one cel stretching the 4 frames. The user is currently on cel 2. Once they hit bake, the
   cel will split into 3 cels: frame 1, frame 2, and frame 3 to 4. the cels in frame 1 and frame 3 to 4
   will not change. However, the cel in frame 2 will have the stream object replaced with an image
   object containing the snapshot of that frame."*
6. *"The paintapp streamer should be low latency and should not lag the main thread. Running it in a
   background thread might be smart, your decision. Note that for the most part, the computer side
   wont move."*
7. *"Just like a video layer, the user should be able to move the stream object in the layer using the
   move tool. The architecture for this is already well established."*
8. *"Note that the user may potentially use many screens or just want to stream a specific app."*
9. *"Note, this part is for the far future. I eventually intend to make the paint app compatible with
   windows, and thus there is the idea that instead of having a separate app, the paint app itself
   contains the streamer. This is a far off feature, but in case the two apps eventually merge, put
   some thought into the design of the architecture of the computer side streamer app. Better to plan
   ahead for potential future changes."*
10. *"There is the case the user may actively stream, then turn off their computer and continue on the
    app, then turn the computer back on and continue streaming."*
11. *"stream layers actively moving do not have to be rendered."*
12. *"The laptop that I want the streamer app in is not this mac but my windows computer. You should
    see it through tailscale."* — it is `desktop-cbr0fl6`, `100.104.85.111` on the tailnet; the iPad is
    `100.70.220.4`. SSH on the Windows box was **closed** on 2026-09-13 and needs the owner to enable
    OpenSSH Server before any Windows-side work can happen from this Mac.

**What is left** — STREAM.md §7 stage 5
- [ ] The owner streams Blender from the laptop to the iPad and rotoscopes over it; source switch,
      window close, laptop lock and reboot behave as STREAM.md §4.5 / §2.8 say.
- [ ] End-to-end latency MEASURED on the real link (a clock on the laptop screen beside the iPad);
      bitrate/GOP tuned if it needs it; numbers into PERFORMANCE.md.
- [ ] The redraw tick's cost MEASURED on the iPad (STREAM.md §8 names the outlet: the
      `ScreenStream` log line or the bar's `streamBar.tickSummary` marker).
- [ ] Owner-verified: Ctrl+V of a bitmap into the drop box (not exercisable over SSH).

---

## (22) Select multiple cels at once

**Status** — not started, and **deprioritised by the owner 2026-09-07**. The menu row exists and is `.disabled(true)` with an empty action; no
cel-selection state exists. The keyframe half of the same idea is real and shipping.

---

## (10) Linear light as an option on the blend mode

**Status** — not started, and **deprioritised by the owner**.

No colour-pipeline setting, no sRGB/linear enum, no transfer LUT, no `Composite.metal` change.

**One adjacent strand did ship**: `ColorMath`'s sRGB↔linear and Oklab conversions feed the gradient
map, which is this item's own "Oklab still gets built, for interpolation" half. The code calls that
**(10a)** in eight places, corrected 2026-09-07 from a stale count of nine — `Effect.gradientTable`,
`EffectSection`, `ColorMathOklabLogicTests`, `EffectParityLogicTests` and `tools/oklab_ramp_ab.swift`
among them. It is finished, so it left this file by the merge rule and the citations stand; see the
convention above.

---

## (37) The brush engine — one stage, and the owner has dropped it

**Status** — stages 0 through 11 merged. **Stage 12, the importers, is dropped for now by the owner**
(2026-09-06: *"skip the importer for now"*), so there is nothing actionable in this item today.

Twenty brushes in five groups with every asset generated and no third-party content; opacity and flow
split with a per-stroke buffer; canvas-anchored texture; the brushes menu and the full-screen editor
with orderable module chains, noise octaves and second inputs; relocatable storage; two-axis scatter.

**Left, when the owner wants it**
- [ ] Stage 12 — the `.abr` / Procreate `.brushset` / Clip Studio `.sut` importers. All three are
      undocumented and reverse-engineered, so the stage opens with a survey against real files, not
      with a parser. Test files are a real dependency. §2.21 makes it an **adapter** onto §6's
      modulation matrix rather than a bitmap reader.

**Owner-side, not ours**: their tuning pass over the other nineteen presets, and driving a real Pencil
to exercise tilt, which no test here can reach. BRUSH.md §13 has **nine** genuinely open questions
(recounted 2026-09-07 — the sixteen bullets split seven answered/closed, nine still open; the "eight"
recorded here was a miscount on the day this line was written, not later drift). Three of the nine
were offered on 2026-09-06 and declined; which three is not recorded here and could not be verified
against a transcript this audit does not have.

**Spec** BRUSH.md — **§2 is thirty-three owner rulings.**

---

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met — (29) shipped in full on 2026-09-06.
- **Interpolation overhaul.** Owner, 2026-10-22: "Interpolation will probably be overhauled sometime
  soon so it works better. I'll let you know in the future." Await that design conversation; do not
  research or implement an overhaul now.
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
