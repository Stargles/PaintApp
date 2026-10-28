# Handoff — active owner-resumed work (Oct 28)

Read this file, then `AGENTS.md`, `CLAUDE.md`, `TODO.md`, `BUGS.md`, and the relevant spec. Kevin
resumed: **continue; do not park**. The full live ask list and deferred tasks remain in `TODO.md`;
items leave only in a qualified merge. Preserve quality/architecture and use one native/compiler
lease at a time. Historical technical detail remains in Git at `63e871d3` and evidence packets.
Before native work, check authoritative lease/status files, including
`/Users/juliapark/PaintWork/s54-final-qualification/root-next-gates.json`; do not infer a PID or
future lease from this handoff.

**New active owner bug:** streamed screen sometimes moves to a different position than its Move
box. Timing question pending; investigate shared stream-window/float placement and late-frame
ownership using existing current/installed-source workflows. No offset/state workaround; preserve
all earlier queue tasks. Recorded in TODO/BUGS before source work.

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

LayerFillView candidate995 still caches render/clip identity before a refused surface mint with no
completion. Source-only audit and followup survive extraction; root recorded in TODO/BUGS before
work. Add an OLD owner-level deterministic refusal→same-request pixel witness; no speculative retry
service/new cache. hcompact owns source-only reproduction, no native until root grants.

### Eraser preview — reference qualification in progress

Tree `PaintApp-s55-eraser-window`. Earlierbfd95b4e normal176/controls9 qualified only the older
slice; root LOOKed six whole owner-landscape pictures. Stronger current-preview versus actual
committed-picture matrices then reproduced missing references (Mode1 six rows, Modes2/4 eight).
Candidate535a0adf removes flat cut/restamp preview APIs and unused replacement raster allocation;
preview/commit share canonical ordered vector geometry and one admitted native window. Independent
review: no concrete source blocker, but posed backing/held-picture, geometric growth and latency
coverage gaps remain. Report `s55-recorded-regressions/eraser-window-source-review-535a0adf.md`.

First535 native selected2 compiled and ran: both RED, no skips. Root reconciled all730 immutable
source entries, methods/device/argv. Mode1 still loses outside/partly covered reference pixels;
Mode2/4 fails a committed red-pixel premise91>220. Agent owns source correction and broader meaningful
replacement tests; no native while it edits. Packet `eraser-native-preview-new2-535a0adf` preserves
originals. Never weaken committed-model pixel parity to pass. Rebuild normal then meaningful new
controls and all affected public classes. No harvest or physical latency/crash claim. Mode3 remains
asynchronous/unchanged from6fb; its source/evidence limits are in `mode3-current-source-map.md`.

### Saved files — current package boundary and next cold Gallery gates

Tree `PaintApp-s54-package-address`, source2905abd5. Whole14classes293 GREEN/root730exact.
One checked address owner rejects traversal, links and wrong entry types before IO, while preserving
literal names/URL kind/probe order. Tidy preflights all generated destinations before any move/rename.
No schema or legal-old-spelling change. Three obsolete PNG-encode counts reuse existing qualified
protected-source/byte/pixel witnesses; no production change in that fixture adaptation.

Original17 controls stopped at10: first9 accepted at10 actual assertions, old10 threw insetup and
gets zero. Narrowed successor8 all assertion_red/restored730; seven premapped targets accepted.
For linked destination, title-rename1094 stayed healthy while direct sidecar-preservation1099 failed.
The observed1099 classification is explicitly post-run, original1094 uncredited. Raw results/maps
unchanged; generic derived extraction was overwritten once, then original-map extraction regenerated
and saved separately beside the observed-map extraction. Root causal receipt states exact limits.

NORMAL Layout38+ordinary Gallery5 passed40/3expected namedskips at exact2905/source730. The older
unchanged293positive is retained. Fresh owned iPad9simE15D8434-9A95-4996-8C47-B1F18E731621 then ran
A-refusal1 and B-open1 GREEN each, root methods/device/argv/source730exact and LOOKed both whole
landscape pictures. Bcomplete3files matched stage/capture AFTER Arefusal BEFORE Bopen. NativeA changed
app-container UUID84833→64CA; original verifier rejected that change. Root's successor read-only proof
uses a fresh authoritative bundle lookup, fixedowned device/nonlinkdirectorychain, projectUUID and
all Bhashes. No stagingreceipt/path edit or assumedrelocationcause. Packet
`package-address-cold-ui-2905abd5` retains all results. Same device now shutdown with data retained;
no reset or physicalinstall. Finalcombined/fast/old-format-retirement gates remain.

**Next native:** newstreamMove selected2 at sourcebe82618f, packet `stream-move-old2-be82618f`;
owned56 reboot in progress, root will start only after join. Source product unchanged fromintegration,
only publictestfixture/helper additions. Eraser source1a4937a7 ready for normal reference/geometry
checks; broad manifest291 (not native-tested), peerreview/faultplan active. 730 means tracked native
source file entries, never test count. Native selectors use actual classes, not sourcefilename.

Stream Move owner report source map is `stream-move-owner-bug-map.md`: relevant placement/frame
code unchanged6fb→integration; default OnTop shares floatView, InPlace composite is asynchronous.
Agent is preparing drawn stream bounds versus Move hull tests for both modes and all landing phases.
No confirmed defect/source change or native run; pending timing answer is not a blocker.

Cold pair real-writer provenance remains packet `package-cold-writer-ff62580e` (seven files, nonce
9D151F05-6036-4457-8D63-0E87F8F25F59). Temporary writer hook retired2c921; no regeneration. The two
permanent Gallery methods are now qualified as above. MotionGroup previous-writer3 remains separate,
prepared/unconsumed.

Owned56 cache housekeeping completed:4.33GBactualfreed, whole9446Container entries unchanged across
clean, archive60012349Bverified. After boot2840existingPaint/Runner entries exact; onlyone584B new
OS SplashBoard downscaled snapshot (AAPLheader,ktxextension), specifically reviewed/retained. Same56
booted, ~18GiBfree. Evidence `s55-recorded-regressions/owned56C-cache-cleanup-20261028`. Other devices,
iPad/artwork, sharedProducts and installed6fb release untouched.

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

Windows refreshed once October28: SSHPC@100.104.85.111 timedout, DesktopCommanderoffline; no further
probe/runtime/build/deploy. Queuemap `s55-recorded-regressions/windows-next-native-map.md`. Artist UI
remaining map `artist-ui-gates-map-20261028.md`, autosave map `autosave-next-native-packet-map.md`.
