# Architecture review — what will hurt the next large feature

Written 2026-08-22 against `main` at `e033c6e`. One question only: **where will a large new feature
cost more than it should?** Nothing here is a rewrite proposal. The app works, it is on the owner's
iPad, and 1,594 fast-tier test functions stand behind it (`grep -c "func test"` over
`*LogicTests|*CharacterizationTests|PerfBaselineTests`).

Measured for this pass: 55,393 lines of app, 45,427 of tests, **15,762 doc-comment lines — 28% of the
app is `///`**. `CanvasManager` is 12 files / 7,382 lines / 91 `@Published`. `CanvasView.swift` is
3,213.

**Status, checked 2026-08-27: finding 1 is closed** — `CanvasTouchOwner` shipped in `38b6fed`, the same
day this file was written (commit `6e1f9ce`), a few commits later. Marked in place at §1.1 and in §4.
Findings 2–4 are unchanged and still open, reverified against `main` at this later date rather than
carried forward from this file's original text — their proposed remedies (`FrameInputs`, a
`writeAtomically` return value, undefaulting `LayerManifest.init`) are not in the tree.

---

## 1. What will actually hurt, ranked

### 1. Nothing answers "who owns this canvas touch" — and this is where the bugs are — CLOSED, `38b6fed`

**Closed, 2026-08-22 (same day, later): `CanvasTouchOwner` shipped as proposed below.** It is a pure
enum in `Models/CanvasTouchOwner.swift`, computed by `owner(in:)`, and it is now what the five
container recognizers in `CanvasView.swift` consult before acting — exactly the "one rule in one
place" the remedy paragraph asks for, replacing the thirteen bespoke guards. Commit `38b6fed` shipped
two behaviour changes the enumeration surfaced beyond the fix itself: 1,678 reachable combinations
where two things acted on one touch (a guide drag that also flooded a fill, a caret placement that
also flooded, the pick tool's colour changing under a fill press), and 118 combinations owned by
nobody, all on a vector layer, closed by a new `.moveBoxCommit` case that puts a floating piece down on
a tap outside it. The analysis below is kept as written — it is the reasoning the type exists to
answer — and is history, not a live task list.

One canvas touch is arbitrated by **fourteen independent decisions across three unrelated mechanisms**,
each spelling its own predicate over the same four inputs (`selectedTool`, `activePanel`,
`floatingPiece`, active-layer state):

| mechanism | sites |
|---|---|
| recognizer `isEnabled` | `CanvasView.swift:868` (catch-all), `:1791` (eyedropper), `:1808` (text), `:1820` (fill) |
| `isUserInteractionEnabled` | `:836` (`shouldInteract`, the layer host), `:1654` (`isCapturingGestures`), `:1713` (shape), `FloatingPieceOverlayView.swift:82`, `ObjectTransformOverlayView.swift:134` |
| `hitTest` override | `ShapeOverlayView.swift:380`, `TextOverlayView.swift:397`, `TextTransformOverlayView.swift:183`, `ObjectTransformOverlayView.swift:220`, `GuideOverlayView.swift:233` |

and `shouldRequireFailure` (`:2676`) reads three of them back out to answer a fourth question.

**The evidence is four defects, three of them in the last week.**
- 2026-08-22, the owner: the pick tool was dead with the Select panel open. `:1791` consulted
  `activePanel`; `:1654` never consulted `selectedTool`; the touch was owned by nobody. Fixed by one
  shared property, `isEyedropperArmed` (`:1636`), whose 20-line doc comment is the whole argument.
- 2026-08-22 (`30e38e3`): dragging a smart shape's *outline* drew a stroke instead, because
  `ShapeOverlayView.hitTest` claimed the handles and nothing else — a different mechanism, same class.
- 2026-08-17: the eyedropper picked a colour **and** painted a stroke, because `shouldInteract`'s tool
  clause was a hand-maintained `!= .fill` list (`Tool.swift:50` records it).
- Still open: "two-finger pan/pinch/rotate is dead while Fill is selected, on device"
  ([BUGS.md:551](BUGS.md)) — unexplained after three attempts.

**What makes it structural, not sloppy**: `activePanel` is `@State` on a SwiftUI view
(`DrawingView.swift:15`), mirrored into the coordinator twice (`CanvasView.swift:333`, `:346`), while
`selectedTool` and `floatingPiece` are on `CanvasManager`. **No single object can see all the inputs**,
so no single function can be written. `DrawingView.swift:199` says this out loud.

**Cost to the next feature.** Every new canvas-touch tool or mode — lasso *move*, the rest of
`ADD_TEXT.md`, a transform mode, a new overlay — is fourteen edits that no compiler checks, in three
mechanisms with different precedence rules. Two of the four defects above cost a device round-trip
with the action recorder to find.

**Smallest useful remedy.** A pure type — `CanvasTouchOwner` — in `Models/`, an enum
(`.activeLayerStroke`, `.selectionOverlay`, `.fillPress`, `.eyedropper`, `.textPress`,
`.floatingPiece`, `.shapeOverlay`, `.catchAll`, `.nobody`) computed by one function from an explicit
input struct passed in (so `activePanel` stays where it is). Every gate above becomes
`owner == .x`. `.nobody` becomes assertable, which is exactly the state the 2026-08-22 bug was.
It is unit-testable the way `Tool.paintsOnCanvas` already is, and it is the one change here that pays
for itself on the *first* new tool.

### 2. What a frame looks like is memoized in eleven hand-written keys

`updateUIView` (`CanvasView.swift:345`) runs **twelve reconcile passes on every SwiftUI pass**,
and any of the 91 `@Published` writes triggers it — 31 views hold `@ObservedObject var canvasManager`.
This is affordable only because each pass is memoized behind a key it invents for itself:
`SandwichKey` (`:1269`), `InterpolationPreviewKey` (`:1859`), `OnionSkinKey` (`:2018`),
`RenderKey` (`TextOverlayView.swift:106`), `FrameBakeKey` (`FrameBakeKey.swift:184`),
`FillKey` (`CanvasManager+Fill.swift:42`), `RasterizeKey` (`PixelOps.swift:133`),
`CacheKey` (`MaskResolver.swift:242`), plus `Key` in `MetalCompositor.swift:233`,
`RasterLayerTexture.swift:58` and `OnionSkinSource.swift:850`.

`FrameBakeKey` is the one that is not a memo at all — it is the **filename** of a baked frame on disk,
so a field it cannot see is the wrong picture served with no error and no second chance, where every
key above it costs one `==` compare after the bucket lookup. It is a hand-written canonical byte
encoder with no `default:` clause for that reason (RENDER.md §3.5).

**A key that cannot see an input serves a stale picture, intermittently.** That is a live bug:
[BUGS.md:566](BUGS.md) — a mask sourced from a *graded group* can be stale, because `MaskResolver`'s
key is built per leaf layer and a folder is not a leaf. `MaskResolver.swift:249` carries a second
instance (`AlphaMask`'s thresholds are statics, so `masks` cannot see them changing — hence
`tuningGeneration`). `InterpolationPreviewKey`'s doc comment enumerates four more inputs that had to be
added because no version number covered them.

**Cost to the next feature.** Anything that changes what a frame looks like from a *new* source must be
added to whichever of the eleven keys can see it, with nothing to say which. The symptom is "sometimes
it doesn't refresh", which is the most expensive kind of bug this app can have.

**Smallest useful remedy.** Not a unified cache. One `FrameInputs` value that each key *embeds* as a
field — `RenderRequest.contentVersions` and `LayerContentVersion` are already most of it — so a new
render input is declared once and the compiler points at every key that must widen. Pair it with the
test shape this repo already uses for caches (`PerfBaselineTests.testDabGradientCacheHitRate`), one per
key: mutate each declared input, assert the key changed.

### 3. A save that fails tells nobody, and one nil PNG fails the whole document

`ProjectStore.writeAtomically` (`ProjectStore.swift:507`) has **three failure returns and all three are
silent**: validation fails → stage to Trash, `return` (`:561`); the pre-save stash fails → `return`
(`:571`); the rename fails → restore the backup, `return` (`:585`). `save`'s own doc says it:
"`completion` runs … once the package is on disk — or once the save has failed, which it does not
distinguish". `ContentView.saveIfNeeded:94` branches on `.ask` and nothing else, so **the gallery
appears exactly as it does on success.**

The failure *atom* is the whole document. `writeCel` writes the raster as `if let data =
png(rasterImage) { write(data, fileName) }` (`:751`) while the manifest still names the file, and
`validateProject` rejects a package whose manifest names a file that is not there — so one nil
`pngData()`, or one failed `try? data.write`, discards the entire save in silence. This was **nearly
shipped**: `ProjectBackupManager.swift:471` records that without the `rasterOmitted` key "every save of
a document with one blank cel would be quietly trashed instead of committed."

`ManifestSkeleton` (`ProjectBackupManager.swift:460`) is a hand-maintained mirror of the manifest's
file references, and it has **already drifted**: `interpolationFileName` is written (`ProjectStore.swift:799`)
and named in the manifest (`ProjectManifest.swift:376`) but is absent from the skeleton, so it is never
validated.

[BUGS.md:131](BUGS.md) already covers the validator's *blind spot* and rules a content probe too
expensive; today's evidence does not change that ruling. It does not cover the **reporting** half.

**Cost to the next feature.** Any large feature adding a per-cel or per-layer sidecar inherits an
all-or-nothing save with no failure channel, and must be registered in the skeleton by hand.

**Smallest useful remedy.** Give `writeAtomically` a return value and hand it to `completion`;
`ContentView` raises the existing `CanvasNotice` banner on failure. The banner machinery is already
built (`canvasManager.raise(.hiddenLayer)` and friends). Roughly thirty lines, no behaviour change on
the happy path.

### 4. One persisted property means four hand-kept structs, and the initializer defaults hide the miss

A layer property that must survive a save is declared four times: `Layer` (`Models/Layer.swift`) →
`SaveSnapshot.LayerContent` (`ProjectStore.swift:160`) → `LayerManifest` (`ProjectManifest.swift:242`)
→ `ManifestSkeleton` if it names a file. **Nine of `LayerManifest.init`'s thirteen parameters are
defaulted** (`:290`), and the decoder is `decodeIfPresent` throughout — both correct, and both
required for the migration story this file argues carefully. The side effect is that forgetting the
snapshot hop *compiles*, writes nothing, and reads back the default.

Nothing generic catches it. What has kept it working is discipline: each feature landed its own
round-trip test (`testGroupPropertiesSurviveARoundTrip`, `testAnExplicitFillReferenceSurvives…`).
That is a good practice depending on an author remembering.

**Smallest useful remedy.** Drop the defaults from `LayerManifest.init` only — keep them on the
stored properties and in `init(from:)`, where the compatibility argument actually lives. The encode
site then must state every field. Nine call sites to update; no behaviour change.

---

## 2. What is genuinely good — do not disturb

- **The compositor is snapshot-pure, and the rule is written down.** `RenderRequest.swift:1-25`:
  "No `@Published` reads, no UIKit view access, no live `RasterLayerTexture`/`VectorCanvas` reads",
  with the reasoning for *why* a lock is not a snapshot. This is what makes byte-for-byte
  CoreGraphics/Metal parity testable at all. **Do not let a new feature hand the compositor a live
  object.**
- **`SaveSnapshot` (`ProjectStore.swift:134`)** — resolve on main, hand the background queue values it
  owns outright. It is what made off-main encoding safe, and `RenderRequest` explicitly cites it as
  the pattern. Copy it for any new background work.
- **`Tool.paintsOnCanvas` (`Tool.swift:54`)** — an exhaustive switch with no `default:`, replacing
  a hand-maintained exclusion list that had already shipped one bug; `ToolLogicTests` walks every
  case. `Tool.textUnavailableReason` is the same pattern over `LayerKind`. This is the shape every
  finding above wants more of.
- **The doc comments are load-bearing, not decoration.** 28% of the app. `isEyedropperArmed`'s comment
  names the bug, the date and the reporter; `PERFORMANCE.md` labels every figure MEASURED or INFERRED;
  `UndoBudget` derives a literal that used to be a guess. **The convention that a non-obvious decision
  carries its reasoning is this codebase's strongest asset.** A large feature that skips it will cost
  the session after it far more than it saved.
- **`Engine/Deform` imports only Foundation, CoreGraphics and Accelerate** — no app types, testable in
  ~5 s with `swiftc`. Keep that boundary.
- **One byte-budgeted `UndoHistory`** for every mutating action, with a documented memory-pressure
  trim. All twelve `recordUndo` sites pass a cost today; note only that the parameter defaults to `0`
  (`CanvasManager.swift:730`), so a new site that omits it retains bytes the budget cannot see.

## 3. What is not worth doing

- **Do not split files by line count.** `CanvasView.swift` at 3,213 lines is one `UIViewRepresentable`
  and its coordinator; `VectorLayer.swift` at 2,335 is `VectorCanvas` (lines 232–2046) plus its value
  types. Splitting either moves the fourteen gates and the eleven keys into more files without changing
  a single one of the findings above. The problem is **which predicate**, not which file.
- **Do not "decompose the `CanvasManager` god object" as a project.** 91 `@Published` on one object
  reads like the headline problem and is not: `REFACTOR_BASELINE.md` records 6.5 ms for a 500-sample
  stroke end to end, and each reconcile pass is already memoized. Extracting the two types in §1.1 and
  §1.2 is the useful 10% of that refactor; the other 90% is churn against 1,594 tests.
- **Do not fix `MaskResolver`'s byte bound or tune any budget** — [BUGS.md:52](BUGS.md) and
  `PERFORMANCE.md` §5 both rule on this. 16 MiB at the owner's canvas; the admission valve never fires.
- **Do not build a dirty-tracking save.** `PERFORMANCE.md` §5, settled for good 2026-08-21, with the
  owner's own "leaving the gallery is instant". Nothing found here reopens it.
- **Do not chase dead fields with a tool.** `Sweep.mode` was real, and a 30-line scan finds one more of
  the same shape — `LatticeExpansion.originalRows` (`Lattice.swift:662`, assigned at `:371`, read
  nowhere; its `originalCols` sibling *is* read). (A second, `BrushGrain.textureName`, was found the
  same way; it is moot now — BRUSH.md §12 stage 2 deleted `BrushGrain` in full, not just the unread
  field.) The same scan flags four false positives — `InterpolationPreviewKey`'s fields, which are
  read only by a synthesized `==`. There is no linter and no warnings-as-errors here, and a check that
  cannot tell a cache-key field from a dead one would be noise. Delete the one that remains; do not
  automate.

## 4. The owner's question, answered

**Yes — large features can be added safely, with one caveat and one thing to do first** (the caveat is
resolved as of `38b6fed`, same day — see below). The parts that are expensive to get right are right:
the render path is pure and snapshot-driven, the save is atomic and backed up, undo is one budgeted
place, the tool and layer-kind switches force the next case to answer, and the reasoning behind every
hard decision is written next to it. Three of today's four findings are additive fixes measured in tens
of lines, not restructurings — findings 2–4 remain open (status note at the top of this file).

The caveat was the touch layer, and it was narrow: **the app had no single place that said who owns a
canvas touch**, and three of the last week's defects were exactly that. **This is done** — `CanvasTouchOwner`
(§1.1) shipped the same day as this review, `38b6fed`, and every tool added after it inherits the
answer instead of re-deriving it.
