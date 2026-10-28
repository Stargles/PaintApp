# Handoff — active owner-resumed work (October 28)

Kevin resumed: **continue; do not park**. Read this file, `AGENTS.md`, `CLAUDE.md`, `TODO.md`,
`BUGS.md`, and the relevant specification. TODO is the complete owner-ask queue; items leave only
in a qualified merge. Preserve architecture, artwork, evidence, and one-native-lease-at-a-time rules.
Historical technical detail and raw results remain in Git and the external packets cited below.

## Integration, install, and protected data

- Integration worktree: `/Users/juliapark/PaintWork/PaintApp-s54-qualified-integration`, branch
  `tmp/s54-qualified-integration`, documentation HEAD `e4f6a15a`. Current package harvest is
  `e4f9c8fa`, with 730 source entries, fast static count 5,424 and full count 6,023. These are
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
and the live lease/status files. Do not infer or reuse a PID. The latest reported native assignment is
eraser normal291 at source `d034036f` in packet
`/Users/juliapark/PaintWork/s55-recorded-regressions/eraser-native-preview-normal291-d034036f/`;
root owns that lease. The preceding `649c1dd6` attempt built zero tests because a benchmark call had
out-of-order argument labels; `d034036f` corrects that call. Check the live state before any action.
No one else should build, compile, or use the simulator concurrently.

### Stream screen and Move box

The new owner report is recorded in TODO/BUGS: a streamed screen can move somewhere different from its
Move box. Timing (held drag, release, or Set Down) is still unanswered; independent work continues.
Installed6fb and integration source have no stream-specific placement change. Do not add offsets or
duplicate transform state.

At old source `0a9461e4`, selected OLD tests produced 2/2 intended RED in both placement modes after
dock clearance and healthy-frame premises. Root reviewed the whole videos: On Top showed the green
stream displaced from the red Move box; In Place picture and box aligned, with a green rotation handle
causing a false-positive pixel probe. This is a real On Top discrepancy, not a qualification pass.
The newer source test `6c6ff97f` uses blue as the new frame, proves no blue is present before arrival,
and checks the whole capture before arrival plus pixel/box parity. It is **not run**. Next: root
reviews that witness and tests the existing post-gesture frame/model-write boundary in the current
stream owner map. Crash evidence traces a post-GESTURE-END model write against the canonical
shown/written map before the fix; confirm this boundary against the new witness before attribution.
Do not infer a product fix or device cause from the old tests.

Evidence and trace: `/Users/juliapark/PaintWork/s55-recorded-regressions/stream-move-old2-0a9461e4/`,
`stream-move-owner-bug-map.md`, and `crash-evidence/` in the recorded-regressions directory. The
separate Test/2048² repeated-tap Move recording and Test1/4096² latency/crash recording remain
preserved; source/build provenance is not established for either recording. Do not conflate them.

### Eraser preview

The previous `bfd95b4e` slice (normal176 plus nine controls) does not qualify the new preview. At
`535a0adf`, two selected native failures came from stale test construction/probe premises; `1a` fixes
those while retaining committed-model parity and adding posed backing, held-picture, growth and
performance coverage. `649c1dd6` reached zero tests (compile-only argument-label error); corrected
source is `d034036f`. The root-reported normal291 run on that source is the next current gate; check
its packet/status before acting. Do not modify the eraser worktree. No assembled-source eraser
qualification, merge, or physical Mode3-crash cause is established. Independent source review found
no concrete blocker but identified coverage gaps; see
`s55-recorded-regressions/eraser-window-source-review-535a0adf.md` and
`eraser-window-peer-review-1a4937a7.md`.

### Layer fill

Fill-window fixture `995677c5` is independently 47/47 GREEN. Its extracted `LayerFillView` means that
candidate's source count is 731; current integration package `e4f9c8fa` remains 730. Do not mix the
censuses. The staged source `393c10ef` adds a default-equivalent surface factory seam and three
selected OLD controls in `WindowSurfaceViewLogicTests` (class count 21): identical render/clip retry
RED; zero-area refusal callback RED; partial second-allocation Set Down lifecycle GREEN. Packet
`fill-owner-refusal-old3-393c10ef` is **PREPARED, not run**. No completion/retry behavior fix has been
authorized yet. Peer review found the key teardown trap: a refusal callback that clears `shownFill`
can make the existing identity-before-nil guard reject Set Down and retain the partial surface. Root
must run selected OLD controls and review that result before authorizing the minimal behavior fix.

The separate reduced-budget manager test that failed to produce `fillLastRender` is still unresolved;
it does not exercise `LayerFillView` and is not proof of user-visible failure. No extra wait, retry, or
weaker assertion. Fixture and receipts: `s55-recorded-regressions/fill-owner-window47-995677c5/` and
`fill-owner-refusal-old3-393c10ef/`.

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

Keep every unfinished TODO item. Immediate source/native queue after checking the lease: eraser normal291
result; stream witness review and post-gesture placement ownership; fill OLD selected3 result and then
root review. Also retain these exact boundaries:

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
