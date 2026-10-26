# Architecture and performance audit — 2026-10-24

The owner asks for clean responsibilities, reusable modules, no zombie/bloated paths, bugs fixed at
their cause, and lower memory/latency without regressions. This is an active programme, not a claim
that all files are reviewed or that every candidate below is a proven runtime bug. Deferred product
features, especially the interpolation overhaul, remain deferred.

## Evidence and scope

Initial source review is pinned to fill revision265e588e. The external inventory, coverage checklist,
source traces and detailed proposals are under `~/PaintWork/s54-architecture-audit/`. Some files are
inventory-only; review those before closing the repository-wide task. Read PERFORMANCE.md before
optimizing. Count resident pictures/bytes and measure real-time changes at2048×1024 first,4096² stress.

Source findings must get a reproduction before a fix is qualified. Use existing owners, queues and
failure paths; do not add a parallel cache/job system. Commit before deliberate faults, restore exact
source afterward, drive affected UI and inspect pictures. Protect real artwork and keep format repairs
one-shot. No evidence below establishes the cause of the Test1/backboardd respring.

Current statuses below replace the initial prepared/unqualified notes; those remain in Git history.
The source-only reconciliation at91940f52 pins current owners and existing receipts, including whole-
file equality for13 of18 selected owner files. That is not a count of reviewed files or new native
qualification. The old19-cluster inventory additionally counted the now-retired temporary converter.

Coverage remains bounded. FontLibrary/TextSettings and selected graph editor lifecycle/context/menu/
subscription ranges received later review without another demonstrated defect. Unread portions of
vector/graph/math/platform/widget internals and private GPU/ImageIO ownership are not certified.
Do not reopen a qualified seam solely because an initial external report says pending.

## Current findings and qualification

| Finding | Root-cause correction through existing owner | Component evidence and remaining boundary |
|---|---|---|
| Migration identity | ProjectLibraryMigration uses strict ProjectFileTree enumeration/type/read/content comparison, not counts/bytes. | Implemented;847/base49. Final assembled gates remain. |
| Trash history ownership | ProjectBackupManager purges by UUID ownership of live/retained Trash packages. | Implemented;847/base49. Retention/startup follow-ons keep their own pins. |
| Export cancellation | FrameExportSession fences old I/O and focus/continuations by the existing run generation. | Implemented;847/base49. No replacement export service. |
| Startup save-stage cleanup | ProjectBackupManager uses ProjectStore.serializingPackageMutation; permanent maintenance owns gallery readiness. | Serializer qualified847/base49; permanent startup59 and separate controls recorded in HANDOFF. Converter is retired after owner confirmation. |
| Thumbnail backfill ownership | Document close cancels its task; backfill checks ownership between bounded batches of8. | Implemented;847/base49. An already-running synchronous batch may finish. |
| Derived frame recovery and baker close | FrameBakeStore separates corrupt disposable data from allocation/ring refusal; FrameBaker close/LatestWins/requeue share actual demand ownership. | Implemented;847/base49. Headroom/unlink/late-write limits remain explicit. |
| Mask dependency budget | ChunkedComposite prices transitive closure/held slots; one MaskResolver checks metadata before pixels and propagates refusal. |847/qualified52 ledger. App-view/recording/Liquify/onion UI controls and final-source gates remain. |
| Video decoder residency | Per-manager VideoFrameSource clients close; pressure trims reader/ring ownership and fences late work. |847/52 ledger. Private AVFoundation pools and up to2 held native samples/reader are outside copied-ring accounting; real device/RSS remains. |
| Stream backpressure/framing/connection | Completion-paced writer, bounded payload/chunks, joined-run/epoch fencing and exact failure settlement. | Swift422/35-gap16 controls; Windows166 Debug/Release and16 targets/15 recipes. Real-link stage5 remains owner/laptop waiting. |
| Destructive test hooks | Compile-time simulator exclusion replaces runtime policy indirection; unused parallel_test.sh removed. | Implemented. Ordinary final app/UI/Release gates remain; never exercise destructive flags on the iPad. |
| Stored palette validation | PaletteColor rejects malformed saved hex; existing backup damage/Trash path preserves original bytes. | Logic422/first29-gap8. Selected recovery UI passed and was LOOKed in676; that whole73-method run was67pass/5fail/1skip. |
| Stationary samples | StrokePathFit bypasses redundant scans; LiveWalk drains prefixes without changing original samples/channels/timing. | Product/parity controls qualified in original126 union. Naive coalescing was refuted by1ULP timing; input storage remains O(N), not bounded. |
| Editable raster residency | One RasterResidency charges sources/working reservations; immutable RasterSource backing/read leases, COW and serialized checkpoints share ownership. |430/finite-pass8/raster14/gap16/remaining35 and scaled cases. Final cold consumers/RSS remain; not eager all-cel hydration or an iPad respring explanation. |
| Brush preview identity/budget | Exact BrushPreviewKey/row result identity and existing8MiB actual-image LRU/pressure owner. |422/first29-gap8; A→B→A UI individually passed676 and3 pictures LOOKed. Whole676 was not green. Final whole classes remain. |
| Vector undo | One VectorUndoCost/UndoBudget prices actual retained payload; generic swaps live in +Undo; stroke Undo uses the edited cel identity. | Original accounting847/52; distinct wrong-cel fix1c passed70/public4/3logic+1public controls, rootLOOK4; harvested d709. Final assembled gates remain. |

Detailed reconciliation and pinned inputs:
`~/PaintWork/s54-architecture-audit/status-reconciliation-91940f52/` (receiptbcc5cca9).
Earlier source traces/qualified ledgers stay under `~/PaintWork/s54-architecture-audit/` and their
original component directories. Historical results are not retagged to current code.

## Genuine remaining work

- Complete assembled-source Debug/Release, affected whole UI/owner pictures, mask consumers and paired
  Release Fill/Lens cost with process-memory/device limits stated. Five original assertion limits
  remain unqualified: stale decoder-error arrangement, two topology checks, packed header metadata,
  and shared slot-array comparisons. They are not five demonstrated unfixed product defects.
- Finish the independently reproduced Tap corner correction through canonical geometry. It is still
  isolated from root: logic37 passed; first public6+benchmark run was6pass/1fail because the new
  landscape test tapped under its card. Root inspected the actual full frames. Preserve every outcome,
  fix that fixture position, and measure image/manager cost before claiming smooth selection.
- Finish the native opacity-gesture experiment and subsequent colour workflows without loosening
  outcomes. Existing observations establish a native slider setup miss, not a blend-product defect.
- Finish current-format damaged-text cold recovery, consumer UI and final integration. Qualified
  strict-decoder/capacity/numeric/seed/text/curve fixes keep their actual pins in HANDOFF.
- Finish genuine file-review gaps. Any further stationary-memory change needs exact-semantics design
  and measured benefit; do not revive refuted coalescing or the deferred interpolation overhaul.
- Physical Test1 allocation/cause and real-link stream stage5 need the actual devices. Do not invent
  a platform-memory fix from simulator counts. Partial compiler-isolation candidates stay out.

A separate source-only review of installed6fb→499017c7 covered the25 changed production paths
(+396/−815) and found no demonstrated duplicate owner, band-aid or abandoned module. It reused actual
retirement/capacity/strict-text/numeric/Undo receipts. It is not a whole-codebase correctness guarantee
or another runtime pass (external benchmark-image-manager-peer-026276cf-499017c7, receipt2a174969).

## Current limits

Component logic and deliberately broken controls are qualified only at their recorded pins. Final
assembled-source Debug/Release, affected cold UI and paired performance gates remain open; root owns
one native slot. Large residency/transport changes retain their existing coherent owners and limits.
Counted capacities are not process RSS or an explanation of the iPad respring. Compiler ownership
annotations that expose a broader unreviewed pixel/primitive boundary remain unharvested; only two
side-effect-free unused locals were pruned. No speculative actor migration or platform-memory claim
is part of the current fixes. Real-link and physical erasing measurements still require the device.
