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

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/render-review.md`.

### Video decoder residency

Shared video ring/readers have no production purge/pressure lifecycle; reader sample buffers need separate bounded accounting measurement.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

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

Used persistent corruption/reset test hooks lack existing simulator-only protection; no actual device damage claimed.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/infrastructure-review.md`.

### Stored palette validation

Malformed saved hex swatch silently resolves to black instead of existing unreadable-library refusal. Valid normal writes unaffected.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

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

Unkeyed preview state can show B after A→B→A cache hit; preview cache has no retained-picture budget.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

Detailed source evidence: `/Users/juliapark/PaintWork/s54-architecture-audit/brush-cel-review.md`.

### Vector undo accounting

Stable element IDs are used as shared-heap proxy and some geometry edits use count*512, undercounting newly retained sample/path payloads.

Remaining: verify/reproduce, then fix or reject the premise with evidence.

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
