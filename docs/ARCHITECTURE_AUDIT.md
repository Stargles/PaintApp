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

## Findings queue

### Migration identity

Equal counts/bytes cannot prove an arbitrary existing destination is the same artwork; strict enumeration/failure semantics also need review.

Unqualified implementation: `tmp/s54-library-ownership` de28149c, six regressions, parse/plutil only.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/persistence-review.md`.

### Trash history ownership

Expiring an old same-named Trash item may delete a different recent item’s backups.

Unqualified implementation: `tmp/s54-library-ownership` de28149c, six regressions, parse/plutil only.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/persistence-review.md`.

### Export cancellation

Cancelled old I/O completion may clear a replacement export’s phase/focus.

Unqualified implementation: `tmp/s54-background-ownership` ec46b3e6, five regressions. No native gate.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/persistence-review.md`.

### Startup save-stage cleanup

Detached startup sweep can overlap the save queue’s active staging directory.

Unqualified implementation: `tmp/s54-background-ownership` ec46b3e6, five regressions. No native gate.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/persistence-review.md`.

### Thumbnail backfill ownership

Old document task remains strong and backfills after close/replacement.

Unqualified implementation: `tmp/s54-background-ownership` ec46b3e6, five regressions. No native gate.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/persistence-review.md`.

### Derived frame recovery

Unreadable existing derived frames can indefinitely retry export; missing/evicted frames may stay clean and fail playback recovery.

Prepared `tmp/s54-bake-lifecycle`: actual reads reject disposable invalid files with per-file accounting;
clean-key resident misses forget/requeue their frames, with allocation/ring refusals kept separate.
Fifteen tiny regression methods across store/baker/export cover drawn bytes, metadata readiness,
real recomposites, close/reset ownership, shared-root caps/accounting, old-read/new-write ownership,
checked hostile-header arithmetic and terminal typed export refusal. Review77278642's filesystem
polling and per-instance ownership blockers are corrected in source; native qualification is pending.
Parse/lints only; native reproduction/qualification,
mutations, current UI/pictures and fast tiers remain root's gates.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/render-review.md`.

### Baker close lifecycle

Retained baker may refill cleared bookkeeping/ring after close; no demonstrated cross-project stale output.

Prepared on the same branch: reuse `LatestWins` cancellation for bake and resident-read landings;
gallery close detaches consumers/model, and reopening creates a fresh owner. Frozen work may finish
one disposable disk write. Queued-job regressions are prepared; native gates remain unrun.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/render-review.md`.

### Mask dependency budget

Source correction prepared: `ChunkedCompositor.minimumSources` prices indivisible transitive mask
closures, assembled node outputs and earlier mix slots; strip height uses that floor in the existing
budget arithmetic. Mix assembly reserves earlier slot pictures while resolving later slots.
`liveMaskRecipe` asks the same mask cache with metadata first, resolving only its dependency subset
on a miss. Nested-mask pixel/count and planner regressions are prepared. Native and mutation gates
remain pending; this bounds planned picture costs, not total process residency, and retains the
minimum-one-row exception when even that row cannot fit.
Live coverage now carries typed source refusal separately from neutral absent/deleted masks. The
stroke factory resolves clipping before any recorder or document mutation and returns an immediate
begin action only on success. The planned playback entry uses the existing rewind rule; take begin
still precedes cel spawn. Refusal raises the shared drawing-read notice. Onion mask/source refusal
uses the existing full blank/cancel/drop path, preventing wrong-frame ghosts and stale landings.
Real declined-provider and planned-frame source tests plus a cold artist-path UI test are prepared;
callback, recording, Liquify and onion refusal need external app-fault/UI qualification because views
are absent from logic. Root's initial focused121 compiled119pass/2 stale one-source premises; their
CPU/Metal replacements now require the true floor2, real nested calls and complete pixel parity.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/render-review.md`.

### Video decoder residency

Source-confirmed lifecycle gap: the shared64MiB ring/four readers had no production close/pressure
owner. `tmp/s54-video-lifecycle` wires per-document closeable clients into the existing source, ring
and MemoryPressure seam; short ownership resets fence old serial reads. Sample diagnostics count
up to two distinct app-held buffers per cached reader separately from ring bytes; AVFoundation
internal pools and RSS remain unmeasured.

Remaining: native tiny regressions/mutants, cold UI/picture at owner size, fast tiers and device
qualification. Source parsing and UI lints alone do not qualify the implementation.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/animation-media-review.md`.

### Stream backpressure

Writer and decoder inputs can queue unbounded work before bounded/latest output; same FIFO delays replacement notice.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/stream-review.md`.

### Stream framing limits

C# declared-u32 allocation unbounded unlike Swift64MiB; receivers do not enforce stated chunk cap.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/stream-review.md`.

### Stream connection ownership

Handshake readiness/current identity and joining client tasks need coherent ownership.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/stream-review.md`.

### Destructive test hooks

The existing compile-time simulator guard originally covered only the Projects/Backups/Trash part of
`-resetGallery`. Its synchronous `AppSettings` half also deletes preferences, and
`-resetEditorPreferences`, `-resetPalettes`, `-resetBrushLibrary`, and
`-simulateProjectCorruption` mutate persistent state. Those hooks now run only in simulator builds;
the app's library-export hooks and temporary-scene seeds remain. Deleted
`deploy/mac/parallel_test.sh` after source, shell-alias and history tracing found no operational
caller; it depended on the retired `~/PaintApp` checkout and old simulator IDs. `fast_test.sh` remains
the documented runner. No actual device damage is claimed. Verification is static only; physical
exclusion follows from the compile-time target branch and is not claimed as simulator XCTest evidence.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/infrastructure-review.md`.

### Stored palette validation

`PaletteColor.color` silently mapped unparsable hex to black. `Palette` decoding now validates canonical
stored swatch hex and sends malformed library data to `AppSettings.readPalettes`' existing refusal;
`PaletteStore` preserves its bytes and refuses edits, and the Palettes view displays its existing notice.
Project-value `PaletteColor` decoding and valid palette wire bytes are unchanged. Added malformed-data
preservation and canonical byte-stability logic tests. No data repair, fallback, migration, or test-only
corruption hook. Static only; no compiler/native/UI/device qualification.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/panels-utilities-review.md`.

### Stationary stroke samples

Pending stroke-fit samples grow during stationary holds; any coalescing must prove timing/brush/take equivalence and actual benefit.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/stroke-geometry-review.md`.

### Editable raster residency

Normal open eagerly allocates a canvas-size editable CGContext per nonblank raster cel; save/freeze ownership must be included in a real byte-budgeted residency design.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/document-residency-review.md`.

### Brush preview identity and budget

Confirmed by source trace at integrated pin `65a8afd8`: `BrushPreviewRow.image` is unkeyed and wins over
the current-key cache value. After A renders, B renders, and A is restored, the cache-hit task exits
without replacing row state, leaving B displayed indefinitely. The singleton cache strongly retains
every unique brush/size/scale image; detached work can finish and insert even after the row task is
cancelled. At the editor's 196×56 points and scale 2, one RGBA8 picture is 175,616 payload bytes;
aggregate process RSS is unmeasured.

The correction is scoped to the existing row/cache seam: completed state carries its request key
(brush value, rounded dimensions and scale), and only a matching result can draw. Cache retention is
bounded by actual image bytes and follows existing `MemoryPressurePolicy` warning/background trims.
BRUSH.md changes from “unedited never re-renders” to retained hits plus deterministic rebuild after
eviction. Qualification needs keyed A→B→A selection and stale completion coverage, byte/LRU/pressure
logic assertions, and a cold editor UI that samples the rendered preview band at A→B→A. No native
result yet.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/brush-cel-review.md`.

### Vector undo accounting

Source-confirmed: stable IDs missed same-ID geometry replacements, flat512 consumers remained,
and Move closures retained unused whole parts. `tmp/s54-vector-undo` replaces the proxy with one
operation-scoped payload accountant, batches affected canvases, and captures only actual Move restore
lists/IDs. Live sample arrays, rest/placement/ancestors and archived fill Data are priced without
unpacking/decoding; inline bytes use a conservative allowance. PackedSampleRun is wire-only.

Remaining: native focused controls/mutations, Debug/Release fast tiers, normal Move/precision UI and
artist-size screenshots/device qualification. Source parse/lints are not footprint or RSS results.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/brush-cel-review.md`.

### Temporary repair startup scheduling

PaintApp.init runs the one-shot conversion synchronously before first UI. Copy-only real-library timer measured11.013s around run() on owned M5 simulator,266 conversions; no iPad startup duration/watchdog claim. Need genuine cold-start reproduction and a minimal temporary scheduling/UI gate before device release. Do not dispatch @MainActor run() onto Task.detached and assume it moved. Retire all repair UI together after owner confirms.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/repair-timing/real-library-report.json`.

## Current limits

The subagents reported account usage limits; their work is committed as WIP and must not be merged
or installed as qualified. Root owns the only native slot. No new device operation has occurred.
Large residency/transport changes need coherent ownership designs; a lazy decode or latest-output slot
alone does not bound visited dirty cels or queued input. Capacity arithmetic is not measured RSS.
The old parallel test script is a prune candidate only after checking live operational references.
