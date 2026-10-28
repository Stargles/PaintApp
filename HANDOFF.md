# Handoff — active owner-resumed work (Oct 28)

Read this file, then `AGENTS.md`, `CLAUDE.md`, `TODO.md`, `BUGS.md`, and the relevant spec. Kevin
resumed: **continue; do not park**. The full live ask list and deferred tasks remain in `TODO.md`;
items leave only in a qualified merge. Preserve quality/architecture and use one native/compiler
lease at a time. Historical technical detail remains in Git at `63e871d3` and evidence packets.
Before native work, check authoritative lease/status files, including
`/Users/juliapark/PaintWork/s54-final-qualification/root-next-gates.json`; do not infer a PID or
future lease from this handoff.

## Current integration and device boundary

- Integration tree: `/Users/juliapark/PaintWork/PaintApp-s54-qualified-integration`,
  branch `tmp/s54-qualified-integration`, recorded HEAD `63e871d3`. Product source remains runtime
  `4cce1817` plus fixture `8ea6a254`; all 730 native source entries byte/mode exact to qualified
  source `c63497f1`.
- At recorded HEAD `63e871d3`, `main`/`origin/main` remain at `afd2030c`; no merge or push had occurred.
  A qualified merge is authorized once the remaining gates pass. Do not treat the separately
  qualified component pins as a qualified assembled integration.
- Installed Release remains source `6fb979f4` (UUID
  `AE3F2323-9760-3783-BB5A-0756F9828CCA`), profile expiry `2026-10-30T00:18:54Z`. It opened
  normally without arguments for at least 20 seconds. No physical gesture test or fresh restart.
  Fresh saved/unlocked export readiness is unanswered; do not restart or install without it.
- Protected original package export:
  `/Users/juliapark/PaintWork/s54-final-qualification/device-install-current-20261025/library-backup/package-export`
  (250 packages; 10 Projects, 221 Backups, 19 Trash; 3,127 files / 544,516,496 bytes). Preserve it
  unchanged. It is pre-conversion data, not a current-format decoder baseline. Older protected copy:
  `/Users/juliapark/PaintWork/s51-cleanup/current-library/Export`.
- Auto-renewal source protection is **activated**, script SHA `655acf67`; it retains verified
  installed source `6fb979f4` while main is older and refuses missing/unrelated ancestry. This is a
  source-only operational change: no device install or daemon change. After any successful manual
  install, atomically update verified source SHA, artifact path, profile expiry/creation and import
  needed private commits into the managed clone. Never advance state before install succeeds. See
  `CLAUDE.md` and `docs/bug-evidence/auto-resign-source-2026-10-28.md`.

## Active regression queue and exact next boundaries

The owner's saved evidence is separate: selection→Move in `Test` / 2048², and drawing/erasing lag
plus crash in `Test1` / 4096². Preserve the recordings and do not conflate causes. The owner says
only the Move-button problem is canvas-specific. Evidence:

- `/Users/juliapark/PaintWork/s54-final-qualification/owner-selection-move-recording-20261028-005920Z/`
  recording SHA `c5f892fe…`; source/build provenance unavailable in header.
- `/Users/juliapark/PaintWork/s54-final-qualification/owner-latency-recording-20261026-214541/`
  recording SHA `94e42359…`; header says Test1/4096², v1.0.43(1), Oct 25 build; exact source not
  verified. Crash/allocation cause remains unproved.

### Stroke landing and filled Undo

Source/runtime `4cce1817` was harvested and fixture `8ea6a254` composed. Original ten whole classes
ran **85/85 GREEN** at source `c63497f1`, root reconciled. Filled/Undo pictures are **portrait**:
four retained outline edges, frame 1, above dock. Guide/Move pictures are owner-landscape. Runtime correction waits only when
interactive edits are pending; no stored policy/cache/service was added. TEMP recorder/delay fixture
was fully retired. This is integrated and simulator-qualified at that exact source; not installed.

### Fill window

Fixture `995677c5` is **47/47 GREEN**, independently reconciled; actual source count was 731 because
`LayerFillView.swift` was extracted. Keep original grant 730 intact and use corrected census receipt.
The separate 85-check drawing/Move integration has 730 entries; it does not yet include this
extraction. Remaining in the fill packet: public growth 1 and fault controls 4, then retirement/final gates. Existing
256×255 and 120×119 fixture stays within the 705600-byte budget and retains output assertions.
Evidence: `/Users/juliapark/PaintWork/s55-recorded-regressions/fill-owner-window47-995677c5/`.

### Eraser window — current native boundary

Tree `/Users/juliapark/PaintWork/PaintApp-s55-eraser-window`, unharvested. Runtime reuses
`CelContentPicture` as the subtractive/replacing backdrop and draws directly into admitted stroke
windows. Vector source excludes references; existing display ownership/pose stay unchanged. Only the
full render's unconditional held-ink clearing was removed. Draw failures use the existing refusal.
No new provider, cache, flag or stored state. Shared clip correction copies transparency instead of
resurrecting erased holes. Existing preview counter moved to actual ordinary overlay publication;
no new metric. Blank test fixtures now exercise admissible painting and actual subtractive coverage.

Successor `2f343024` ran **165/165 GREEN**, exact730/method/device/argv reconciled. OLD `9b` had
independently reproduced the two stale blank tests and the shared clip defect. However root LOOK
found the short erased target apparently visible in the first app picture and gone after12s; the
original public test checked exterior ink/model but not the erased pixel. **HOLD qualification**.
`44c2bbdd` adds only direct white-before/ink-before/white-immediately-after guards and whole-screen
captures, measures paper after configuration, retaining original delays/wait/counts/exterior checks.
Selected public1 **fails only immediate white-target assertion245**, after white-before and both
ink-before premises pass; root reconciled730/method/device/argv and LOOKed the whole final-video
frame: both marks remain. Packet `s55-recorded-regressions/eraser-direct-target1-44c2bbdd/`.
Later count/trace/exterior/model assertions were not executed on this failing method. Exact method:
`Mode1UITests/testMode1KeepsDisjointPendingInkVisibleThroughEraseAndRenderWait`.
OLDeee focused logic isolates the same defect: transparent replacement hole had alpha255. Shared
correctionbfd95b4e explicitly skips original ink when outside-patch path is empty; no new state,
cache, service or wait. **Current166 GREEN**, root730/method/device/argv exact. Root LOOKed both
whole owner-landscape screen captures: upper target absent immediately and after12s; lower ink
intact. `s55-recorded-regressions/eraser-corrected-picture166-bfd95b4e/native-run01` has source/outcome/
picture receipts. Controls8 and whole Mode1/Cutting/Picker11 remain before harvest. No device claim. Whole affected UI/fault controls, final gates and device evidence
remain. No crash-cause or physical latency claim.

### Package migration / tidy

OLD `6fee` ran one intended partial-migration witness and reached its intended RED after setup passed.
XCTest catches thrown reads and continues, so later preservation checks ran but do not discriminate
this boundary. Prior `9d` setup failed on overlapping cels (934/935), zero credit. Causal review `v2`
is authoritative. Candidate NEW `bf1c9113` in `PaintApp-s54-package-address` has 38 tests,
**not qualified**: preflight every generated target globally before moves,
reuse checked resolver/CAS, preserve spellings and decoder, and refuse whole plan if any target is
occupied; remove old per-item skip. Its first whole38 native attempt built **0 tests**: the earlier
checked-write change left a local ProjectStore.write wrapper missing `throws` although its callers
already propagate it. Bounded signature correction7eafe7d9 committed in source branch; rerun38 before
wider package/fault/UI gates. No migration qualification yet.

## Other prepared work and still-open owner asks

Keep every queue item in TODO, including autosave `4c`, export `694`, gradient `8e`, resize `ac`,
source cleanup, end-to-end/device checks, Windows work and explicitly deferred tasks. Useful current
packets:

- Autosave inventory: `/Users/juliapark/PaintWork/s55-recorded-regressions/autosave-next-native.md`.
- Previous-writer provenance, strict decoding and one-shot package repair remain governed by TODO
  and specs: preserve the real previous-writer package; current decoder fails loudly; saved-format
  changes need one-shot repair across Projects, Backups and Trash, deleted after owner confirmation.
  Do not mutate protected artwork during inventory.
- Export `694bdf49`: source-only; current `ToolPanels` count is 20 (not 13). Actual Share
  dismissal/close-return and cancel→drawing/gesture checks remain. Fresh saved/unlocked export
  question unanswered.
- Gradient `8e5d100e`: whole 15 + public 1 prepared, native unrun; inspect current packet/gates.
- Resize `ac`: corrected drawn/Undo premise and visible progress checks remain.
- Source cleanup, full architecture review, Windows DNS/resource/Quit and real-link owner/laptop
  checks remain. Device Test1 respring needs fresh physical evidence. Interpolation overhaul,
  multi-cel selection, linear-light blending, audio/video editor and dropped brush importers remain
  deferred exactly as TODO records; do not research/reopen without owner direction.
- TODO contains the complete live owner ask list, historical qualifications, and exact remaining
  gates. Do not copy stale historical “park” prompts forward as current instructions.

## Lease, evidence, and safety rules

- Before native/compiler work, read live `root-next-gates.json` and confirm current lease owner/status;
  recheck immediately before starting. Do not infer a PID or future lease from this document.
- Keep native work serialized; root owns the native lease. No overlapping build/test/compiler or
  simulator. Preserve result bundles, originals and source pins. Do not reset a shared ref, stash,
  mutate protected artwork, or run cleanup against unowned scenes.
- Source-only, integrated, installed, and qualified are different states. A green component pin does
  not qualify the assembled source; an install does not prove physical workflows. Record exact source,
  methods/device/argv and actual assertions reached. Inspect which assertions execute: XCTest catches thrown assertion autoclosures and can continue,
  while uncaught throws stop a method. Later execution alone does not prove a discriminating oracle.
- Follow `AGENTS.md`/`CLAUDE.md`: own simulator per run, `tools/simlock.sh`, serial testing, fast tier
  verbatim in Debug and Release, reconcile `totalTestCount`, lints/PBX/graph checks, affected UI
  classes, mutation-test new assertions after commit, and look at owner-landscape screenshots. Say
  what was not run. Never claim a full suite per item.
- A qualified merge is authorized once remaining gates are met; push status remains unchanged. Before
  any install: fresh owner readiness, protected library, old-scene drives (playback, pan from
  grey, Move box, graph drag/release, stroke), signed clean Release and profile-life checks. After
  successful install update renewal state atomically. Use existing repo merge rules for the qualified
  merge; no new install or restart authorization is implied.

## Reporting

Keep reports short and artist-facing: root cause; changed/deleted files and symbols; exact merged SHA;
Debug/Release fast counts; UI classes added/run; what was driven and seen; what Kevin does next; any
refuted premise; and anything not run. Ask only a concrete owner decision when a ruling is required.
