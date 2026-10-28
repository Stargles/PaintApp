# Handoff — active owner-resumed work (October 28)

New active owner Move handoff report: after moving a selection, switching to Brush/Erase briefly
hides the placed drawing. Owner's theory is early preview retirement; explicit preference is keep
same lifted picture until composited base actually lands, accepting temporary raw overlay. Recorded
in TODO/BUGS before investigation; reuse existing held-content/revision retirement, no timer/newcache.
This adds to (does not replace) stream offset, Test Move/lag/crash and the rest of TODO.

Kevin resumed: **continue; do not park**. Read this file, `AGENTS.md`, `CLAUDE.md`, `TODO.md`,
`BUGS.md`, and the relevant specification. TODO is the complete owner-ask queue; items leave only
in a qualified merge. Preserve architecture, artwork, evidence, and one-native-lease-at-a-time rules.
Historical technical detail and raw results remain in Git and the external packets cited below.

## Integration, install, and protected data

- Integration worktree: `/Users/juliapark/PaintWork/PaintApp-s54-qualified-integration`, branch
  `tmp/s54-qualified-integration`, documentation HEAD `f9faf3e8` before this reconciliation. Current
  package harvest is `e4f9c8fa`, with 730 source entries, fast static count 5,424 and full count 6,023. These are
  static counts only: this assembled source has **not** passed its final native gates.
- Main/origin remain `afd2030c`; no merge or push. A qualified merge is authorized after remaining
  gates pass. Component qualification and harvested source do not qualify the assembled integration.
- Installed Release is still source `6fb979f442f4d3da1299785de2a077a2058a4dfe`, UUID
  `AE3F2323-9760-3783-BB5A-0756F9828CCA`, profile expiry `2026-10-30T00:18:54Z`. It launched
  normally without arguments for at least 20 seconds; no physical gesture run is established.
  No fresh saved/unlocked export readiness has been given. Do not restart or install on that basis.
- The 250-package export at
  `/Users/juliapark/PaintWork/s54-final-qualification/device-install-current-20261025/library-backup/package-export`
  is protected and unchanged: 10 Projects, 221 Backups, 19 Trash, 3,127 files / 544,516,496 bytes.
  It is pre-conversion data, not a current-format decoder baseline. Older protected copy:
  `/Users/juliapark/PaintWork/s51-cleanup/current-library/Export`.
- Auto-renewal source protection is activated at script SHA `655acf67`, retaining verified installed
  `6fb979f4` while main is older. Update its source/profile state only after a successful manual
  install. No device or daemon change was made by this source protection. See
  `docs/bug-evidence/auto-resign-source-2026-10-28.md`.

The stroke-landing runtime `4cce1817` plus fixture `8ea6a254` passed its 85-check component run at
source `c63497f1` (source730, reconciled). Filled/Undo captures are portrait; Guide/Move captures are
owner-landscape. This is integrated component evidence, not installed or final assembled qualification.

## Current gates and exact next boundaries

Before native/compiler work, re-read `/Users/juliapark/PaintWork/s54-final-qualification/root-next-gates.json`
and the live lease/status files. Do not infer or reuse a PID. Current joined results are RED or unrun;
root owns native execution. No one else should build, compile, or use a simulator concurrently.

### Stream screen and Move box

The new owner report is recorded in TODO/BUGS: a streamed screen can move somewhere different from its
Move box. Timing (held drag, release, or Set Down) is still unanswered; independent work continues.
Installed6fb and integration source have no stream-specific placement change. Do not add offsets or
duplicate transform state.

At old source `0a9461e4`, selected OLD tests produced 2/2 intended RED in both placement modes after
dock clearance and healthy-frame premises. Root reviewed the whole videos: On Top showed the green
stream displaced from the red Move box; In Place picture and box aligned, with a green rotation handle
causing a false-positive pixel probe. This is a real On Top discrepancy, not a qualification pass.
Source `131475f7` contains the On Top correction: return each live child from already-written
geometry into the bitmap's latched pose before the parent Move is applied. Authored cel pose stays
in its existing order; unchanged geometry returns its original pose. No extra stored transform.
Whole146 at `214617d3` passed145 and failed the new unit's coordinate convention; all7 public
stream workflows passed. Test-only131 fixes that centered-view convention; focused2 passed2/2.
Two deliberate faults then produced assertion RED (old On Top route and reversed authored-pose
order), restoring all730 source entries. Generic/manual causal extraction is pending. A normal
post-fault rebuild of selected2 is currently running; do not reuse mutated Products. No final
whole146 or assembled-source qualification, harvest or installation is claimed.

Evidence and trace: `/Users/juliapark/PaintWork/s55-recorded-regressions/stream-move-old2-0a9461e4/`,
`stream-move-owner-bug-map.md`, and `crash-evidence/` in the recorded-regressions directory. The
separate Test/2048² repeated-tap Move recording and Test1/4096² latency/crash recording remain
preserved; source/build provenance is not established for either recording. Do not conflate them.

### Eraser preview

The previous `bfd95b4e` slice (normal176 plus nine controls) does not qualify the new preview. The
`d034036f` normal291 run in `/Users/juliapark/PaintWork/s55-recorded-regressions/eraser-native-preview-normal291-d034036f/`
is **RED**: 286 passed, 3 failed, 2 named opt-in skips. The failures were
a preview fixture expected24/got0, a cache-hit premise expected1/got0, and an 8/16384-pixel Mode1
coverage mismatch. Test-only successors correct cache-lifetime and brush-premise fixtures, restore the intended hard
opaque brush, and add growth protection. The new public Mode1 held In-Place reference workflow is
committed. Source `9c4da00e` fixes its optional pixel types after447 compiled zero tests. Selected11
and13 deliberate faults remain unrun at9c. The broader291 run did pass all11 prior public eraser
workflows and the bounded200-stroke parity/cost check; root inspected six whole pictures. Simulator
counts:1,117 brush marks versus33,400 full-scene;57,408 window pixels versus4,194,304 canvas pixels. Do not modify the owned eraser worktree before
handback. No assembled-source eraser qualification or physical Mode3-crash cause is established.
Independent source review found no concrete blocker but identified coverage gaps; see
`s55-recorded-regressions/eraser-window-source-review-535a0adf.md` and
`eraser-window-peer-review-1a4937a7.md`.

### Layer fill

Fill-window fixture `995677c5` is independently 47/47 GREEN. Its extracted `LayerFillView` means that
candidate's source count is 731; current integration package `e4f9c8fa` remains 730. Do not mix the
censuses. `fill-owner-refusal-old4-57073ba1` is the latest OLD run: **RED**, 1 pass and 3 failures at source731.
Callback and retry controls reached their intended RED assertions; ABA passed; partial-release failed
at a combined assertion, leaving its lifetime premise unresolved. Test-only pool fix `c056` is
committed but unrun; no fill behavior correction is established. Run the corrected selected controls
and review exact reached assertions before any runtime fix. The older old3 packet is superseded.

The separate reduced-budget manager test that failed to produce `fillLastRender` is still unresolved;
it does not exercise `LayerFillView` and is not proof of user-visible failure. No extra wait, retry, or
weaker assertion. Fixture and receipts: `s55-recorded-regressions/fill-owner-window47-995677c5/`,
`fill-owner-refusal-old3-393c10ef/` (superseded OLD plan), and
`fill-owner-refusal-old4-57073ba1/` (latest RED OLD run).

### Saved-file package boundary and cold Gallery

Package source `2905abd5` passed its 293-class component run and Layout38 + Gallery5 (40 passed, 3
expected named skips) at source730. The two separate cold Gallery workflows also passed: damaged A
was refused; B's complete files were verified before B opened and B drew its own blue. Root reviewed
both owner-landscape pictures. This is component evidence, not final combined qualification.

The earlier 17-control batch stopped at ten: first nine accepted, case ten threw during setup and
gets zero credit. The narrowed successor eight produced intended assertion RED/restoration; linked
sidecar preservation was observed after the run, while the earlier title-rename assertion remains
unproved. Preserve original plans/results and derived extractions. Strict old-format cleanup still
requires a real previous-writer MotionGroup package before changing the four-field decoder boundary:
source `28c08b26`, previous-writer package 729 / PBX1329, prepared three-control launch, nonce
`B2BAF2AC-3B98-4DEE-95F0-7FD07268E811` remains unconsumed. Do not regenerate or consume it without
the existing one-shot protocol. Cold Gallery packet: `package-address-cold-ui-2905abd5`.

## Remaining owner queue

Keep every unfinished TODO item. Immediate queue after checking ownership: stream normal post-fault
rebuild/causal extraction/harvest; eraser9c selected11 and13 faults; new Move-exit OLD public2; fill
selected OLD controls after `c056`. Also retain these exact boundaries:

- Autosave `4c`: inventory and deliberate failure/reopen controls remain in
  `/Users/juliapark/PaintWork/s55-recorded-regressions/autosave-next-native.md`.
- Export `694bdf49`: ToolPanels class count is 20. Drive actual Share dismissal/close-return and
  cancel → drawing/gesture checks. Fresh saved/unlocked export readiness is unanswered.
- Gradient `8e5d100e`: whole15 plus public1 are prepared, native unrun. Check current packet/gates.
- Resize `ac`: use the corrected drawn/Undo premise and complete visible-progress checks.
- Source cleanup, architecture review, final assembled Debug/Release/UI gates, and owner-device
  workflows remain. Do not remove finished owner asks from TODO before a qualified merge.
- Windows DNS/resource/clipboard/keep-awake/awaited-Quit work remains. The last single probe on
  October28 timed out at `PC@100.104.85.111`; Desktop Commander was offline. Do not repoll until an
  external state changes. Real-link stage needs the owner/laptop. Map:
  `/Users/juliapark/PaintWork/s55-recorded-regressions/windows-next-native-map.md`.

Previous-writer strict-decoder capture, one-shot repair and protection of Projects/Backups/Trash remain
required. Preserve the prepared MotionGroup data above. Fresh saved/unlocked export readiness and any
physical restart remain unanswered. Test1 respring needs fresh physical evidence. Do not touch the
protected export during inventory.

Deferred exactly as TODO records: interpolation overhaul, multi-cel selection, linear-light blending,
audio/video editor and dropped brush importers. Do not reopen them without owner direction.

## Qualification and safety boundary

Keep **source-only**, **integrated**, **installed**, and **qualified** distinct. A component green does
not qualify assembled source; installation does not prove physical workflow. Record exact source,
class/method counts, device, argv, and which assertions were actually reached. XCTest can catch a
thrown assertion and continue into later assertions, so later execution is not itself proof of a
healthy premise. Preserve original evidence and result bundles.

Follow `AGENTS.md`/`CLAUDE.md`: own simulator, `tools/simlock.sh`, serial testing, fast tier verbatim in
Debug and Release, reconcile `totalTestCount`, lint identifiers/helpers, check PBX/graph, run affected
UI classes, mutation-test after commit, and inspect owner-landscape captures. Report what was not run.
Before any install, require the fresh owner readiness, protected library, old-scene drives (playback,
pan from grey, Move box, graph drag/release, stroke), clean signed Release and profile-life check; only
after successful installation advance renewal state atomically. A merge is authorized once all gates
pass; push status is unchanged.

## Reporting

Keep the report short and artist-facing: root cause; changed/deleted files and symbols; exact merged
SHA; Debug/Release fast counts; UI classes added/run; what was driven and seen; what Kevin does next;
refuted premises; and anything not run. Ask only a concrete owner decision when a ruling is required.
