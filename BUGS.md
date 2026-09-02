# Known Issues

Open items only — fixed entries are pruned, and the fix lives in the commit and the code comment.
One section per bug, newest first.

## A 16383² canvas draws nothing the artist can see, and the allocation is not why (2026-09-02)

The owner, on their own iPad 9 (3 GB, A13), **Release build 1.0.43 of `41eafa9`**, on a canvas created at
the size picker's maximum: *"Although it does not crash, it is broken. First off, the brushstroke
disappears when you draw. Secondly, the framerate is very laggy."*

**The obvious diagnosis is wrong, and half of this entry exists to say so.** It was that
`VectorCanvas.render()` opens a `UIGraphicsImageRenderer` at canvas size, that 16383×16383×4 is 1.00 GiB
against roughly 1.4 GiB of headroom, that the allocation therefore fails, and that neither
`UIGraphicsImageRenderer` nor `CGContext(...)` traps on failure — so the committed stroke would be drawn
into nothing while the live scratch, bounded by RENDER stage 0, went on showing. The last step is true and
irrelevant; **the load-bearing one is false, because the allocation succeeds.** MEASURED on the owner's
device, Release, at `41eafa9`, one dab on an otherwise empty cel:

| canvas | `VectorCanvas.render()` | bare canvas-sized fill | `RasterLayerTexture` stamp + read | image produced | ink present |
|---|---|---|---|---|---|
| 2048² | 3.7 ms | 4.8 ms | 14.2 ms | 2048×2048 | yes |
| 4096² | 5.1 ms | 36.4 ms | 0.6 ms | 4096×4096 | yes |
| 8192² | 17.4 ms | 138.6 ms | 1.1 ms | 8192×8192 | yes |
| 12288² | 43.7 ms | 312.7 ms | 0.6 ms | 12288×12288 | yes |
| **16383²** | **143.5 ms** | **489.5 ms** | **0.9 ms** | **16383×16383** | **yes** |

A canvas-sized `CGBitmapContext` is lazily committed, which is why the raster column barely moves: the
pages a dab never touches are never faulted in. The 1 GiB buffer is not the problem, it is not even
expensive to *hold*; it is expensive to *clear and walk*, which is the second complaint, not the first.

**What the artist actually cannot see had two measured causes, neither of them an allocation. (a) is
fixed; (b) is what is still open here.**

**(a) Artwork was minified by Core Animation's default `.linear` filter with no mipmaps, and a default
stroke is thinner than one screen pixel — FIXED, the nine artwork layers ask for `.trilinear`.**
`magnificationFilter` was set on every view that shows artwork and `minificationFilter` on none of them,
so they all ran Core Animation's default `.linear` minification, which has no mipmap chain.
`CanvasManager.brushSize` defaults to **5 canvas points** (`CanvasManager.swift:497`) and the canvas opens
at `fitScale` (`CanvasView.swift:2607`). MEASURED — a 5-point line drawn into a canvas-sized image and
minified to a 400-point viewport, point-sampled (what an un-mipmapped `.linear` degenerates to at these
ratios) against box-filtered:

| canvas | fit scale | stroke width on screen | point-sampled ink | box-filtered ink |
|---|---|---|---|---|
| 2048² | 0.195 | 0.98 pt | 800 px | 800 px |
| 4096² | 0.098 | 0.49 pt | **0** | 800 px |
| 8192² | 0.049 | 0.24 pt | **0** | 800 px |
| 12288² | 0.033 | 0.16 pt | **0** | 800 px |

**From 4096² up, a default stroke seen at fit zoom was not faint — it was gone**, and gone identically in
the live scratch and in the committed render, because both are canvas-resolution images under the same
transform. It was enough on its own to produce "the brushstroke disappears when you draw", it needed no
16k-specific mechanism, and it reached 4096² documents. The table is kept because it is the provenance of
the fix and because it is still what `.linear` does: **the mipmap chain is the whole of the repair, and
nothing measures it on the device yet** — `CanvasLayerFilterLogicTests` pins the property, not the pixels.

**(b) At 16383² the image cannot be put on screen at all.** Same run: a `UIImageView` holding a
canvas-sized image inside a container at `fitScale`, read back through `CALayer.render(in:)`, showed the
band at 2048², 4096², 8192² and 12288² and showed **nothing** at 16383². And drawing that same 16383²
`CGImage` into a 400×400 `CGContext` — which is what any downscale of it is — **killed the test runner
process**; the run restarted and finished the remaining cases. (`drawHierarchy(afterScreenUpdates:)` was
also tried and returned false at every size, because the probe's window had no scene: that half is void
and the render-server behaviour is still unmeasured.)

So the pixels exist and nothing reaches the screen — the opposite failure from the one hypothesised, and
one no budget check on the allocation would have caught.

**And (b) reproduces the owner's sentence more exactly than (a) did, which is why both are here.** The
live scratch is its own small image at `windowRect`, not the canvas: on a one-inch drag at 16383² that
window measured 8617×8611, between the 12288² that displayed and the 16383² that did not, and it is a
band of about 8639×134 now that each axis pads itself. INFERRED, not measured: **the scratch is
displayable and the committed 1 GiB render is not, so ink appears under the pen and vanishes at lift** —
which is what "the brushstroke disappears when you draw" says. The band makes that inference stronger
rather than weaker, since the scratch is now well under every size that displayed.

**What stage 2 changed and what it did not.** On today's `9c9d435` the committed re-render is deferred to
`StrokeCanvasView.renderQueue` and the finished stroke's scratch is held until it lands
(`refreshDisplay(waitingForTheRender:)`, RENDER §2.13). That is correct and it removes 143.5 ms from the
main thread at pen-up — but it changes neither cause above: the render still allocates and walks the same
canvas, and the image it produces still has to be minified onto the screen by the same filter. **The
numbers above carry to `9c9d435` unchanged because the code they measure did not move**:
`git diff 41eafa9 9c9d435 -- Engine/StrokeScratch.swift` is empty, and `VectorCanvas.render`'s body is
byte-identical, lifted into `renderLocked(quality:)` so `render(quality:ifStillAtVersion:)` can share it.
Expect the same symptom with a different shape: the scratch stays up longer rather than the layer going
blank. **That last sentence is INFERRED and is the one thing here nobody has watched** — it needs an
XCUITest that reaches the editor on this device, which is the open entry "XCUITests cannot launch into the
editor on the iPad 9", or thirty seconds of the owner's own time.

**What is left, cheapest first.**

1. **Bound the canvas the display can actually show.** 16383² is past what this device will composite
   whatever the filter says, so `.trilinear` does not reach it. Either cap `maxCanvasExtent` at a size the
   display path is measured to survive, or give the layer views a tiled/downsampled presentation image
   instead of the native one. BUGS' "Raising the canvas maximum reaches a raster-storage cost
   `CompositorBudget` never bounds" (2026-08-27) flagged the storage half of this; the display half was
   not known.
2. **A mipmap chain is about a third more texture per displayed layer and `CompositorBudget` does not
   account for it.** That gap is PERFORMANCE §9 item 5 — nothing counts what Core Animation holds — and
   the filter is now one more tenant of it. No measurement exists of what the chains cost on the device.
3. **A brush size expressed in canvas points is a trap at any large canvas.** Not a bug on its own — see
   PERFORMANCE §9 item 3 — but the reason (a) was invisible to whoever picks the default.

## A stroke dab straddling a canvas edge rebuilds the scratch window on every dab (2026-09-02)

`StrokeScratch.window(containing:)` returns the existing window only when `windowRect.contains(rect)`.
Once the window has been clamped to the canvas by `.intersection(canvas)`, a dab that straddles that
edge is never contained — so every such dab takes the reallocation path, recomputes an **identical**
rect, and pays a full `contents(for:)` copy of the window to produce the buffer it already had.

Pre-existing, and unchanged by the band fix (PERFORMANCE §9 item 1): that change makes each copy much
cheaper without making them fewer. It bites hardest exactly where the artist draws along an edge, and
on a large canvas where the window is biggest.

The fix is to return the existing window when the recomputed rect equals `windowRect`, before
allocating. Two lines. Left out of the band change deliberately, as a second behavioural change to one
function that the pin for the first would not have covered.


## Memory allocation audit — twelve sites, ranked (2026-09-01)

Found while designing RENDER.md; the compositor's budget is sound and almost nothing else consults it. RENDER §5 stage
7 takes these. Canvas bytes are `w·h·4`: 8 MiB at 2048x1024, 64 MiB at 4096², 1 GiB at 16383².

1. **`renderSources` holds one canvas-sized image per visible leaf, all at once, with no budget**
   (`Engine/RenderRequest.swift:884-993`). `affordableSize` bounds the canvas, never the count: 100 leaves at 2048x1024
   is 800 MiB. RENDER §3.4 is the fix.
2. **Nothing on the live-stroke path consults `hasHeadroom`**, which has exactly one call site
   (`Engine/MetalCompositor.swift:620`). The stroke itself no longer needs it — `Engine/StrokeScratch.swift` bounds the
   scratch by the stroke's own dirty rect rather than by the canvas, on both tiers — but committing one still opens the
   cel's canvas-sized `CGContext` (`RasterLayerTexture.ensureContext`), which is the artwork's own storage and is as
   unbudgeted as everything else here.
3. **`MetalFillSession` allocates ~34 bytes per canvas pixel with no budget and no headroom check**
   (`Engine/MetalFillEngine.swift:300-380`; 44 with a lasso and two colours) — 544 MiB at 4096². `compositeReferenceRGBA`
   (`Models/CanvasManager+Fill.swift:842-852`) adds a transient canvas-sized image and byte array.
4. **Blanked layer hosts keep every byte.** `Views/Canvas/LayerHostView.swift:97-103` `setBlanked` only installs a
   zero-alpha mask; `reconcileLayers` (`CanvasView.swift:892`) still re-renders blanked hosts every pass. The sandwich's
   three composites are paid on top of N × 3 host images, not instead of them.
5. **Two caches are bounded by entry count, which is not a bound.** `MaskResolver.cache` is 8 entries
   (`MaskResolver.swift:336`; 128 MiB at 4096², 2 GiB at 16383²), and `vectorRenderCacheLimit = 12`
   (`Models/CanvasManager+Interpolation.swift:489-511`) holds up to two canvas images each, is evicted only from the Move
   tool's `handleActiveContextChanged` (`SelectionModels.swift:249`), and has no pressure hook at all — 768 MiB to 1.5 GiB
   at 4096². **And that one call site runs on every playback tick**: `currentFrame.didSet`
   (`Models/CanvasManager.swift:736-743`) calls `handleActiveContextChanged`, whose evictor counts every vector cel in the
   document, finds any real document past 12, then walks every cel again taking each canvas's lock through `hasCachedImage`
   (a lock a background `render()` can hold for tens of milliseconds), builds an array and sorts it — O(cels) plus a sort, on
   the main thread, 24 times a second for the whole of playback. The fix is a byte budget on `PixelOps.rasterizeCache`'s
   rule, eviction over a registry of canvases that actually hold a render rather than a document scan, run when a render is
   cached rather than when the frame changes, and the call at `SelectionModels.swift:249` deleted.
6. **Every eviction signal is a `UIApplication` notification and the only valve is `os_proc_available_memory`**
   (`PixelOps.swift:237,247`; `MetalCompositor.swift:401,413`; `MaskResolver.swift:363`; `OnionSkinSource.swift:948`;
   `CanvasManager.swift:1098`; `Engine/Compositor.swift:217`). RENDER §2.6 rules portability; a `MemoryPressure` seam
   with an iOS implementation is the shape.
7. **The Metal upload cache's budget collapses to zero on any 4K document.** `CompositorMetalEngine.attempt` gives it
   `textureBudgetBytes` minus what every resident size's walk holds, and three walk textures at 4096² are the whole
   192 MiB budget on a 3 GB device — so `trimToBudget` empties the cache after every composite and the cache does not
   exist at the sizes it would help most. Losing is by design (`UploadCache`'s own doc: it is the one part of the
   working set whose absence costs only time), but it is silent, and the degradation is a cliff rather than a slope.
   Nothing reports the hit rate outside `PerfBaselineTests`.
8. **Vector element undo charges a flat 512 bytes per element** (`Models/CanvasManager+Text.swift:415`) while a
   `VectorElement.image` carries a whole `UIImage` (`VectorLayer.swift:263-269`).
9. **`OnionSkinRasterCache` computes its limit from the newest entry's size** (`OnionSkinSource.swift:918-923`), so
   after a Half → Quarter change 84 MiB can sit under a 64 MiB budget.
10. **`Cel.thumbnail`, one `DabGradientCache` per cel and one `StrokeSpatialIndex` per vector canvas have no global bound**
    (`Models/Cel.swift:26`; `RasterLayerTexture.swift:123, 472`; `VectorLayer.swift:564`).
11. **`LayerRenderSource.solid` renders a full canvas to express one colour, per value layer, per rebuild, unmemoised**
    (`RenderRequest.swift:84-101`).
12. **`SaveSnapshot` renders every content-bearing cel and copies every vector cel on the main actor, all live during the
    write** (`ProjectStore.swift:134-305`).

The five declared budgets sum to 656 MiB at 2048x1024 and are pinned to; add the undeclared ones above and one live
rebuild reaches 850-950 MiB before a single cel of the document, against the ~1.4 GiB the repo cites as pre-jetsam
(`Compositor.swift:102`). At 4096² the two count-bounded caches alone push the sum past that ceiling.

**All twelve are still open at `9c9d435`, and the device has now been asked about them — see
[PERFORMANCE.md](PERFORMANCE.md) §9, which ranks them against three sites this list misses and corrects two
things stated here.** Item 1's site is now `FrameRecipe.resolveSources` (`Engine/FrameRecipe.swift:88-115`):
stage 2 moved it off the main actor and left it exactly as unbudgeted, so only the thread changed. And the
`w·h·4` column above is the *nominal* size, not the resident one — a CoreGraphics canvas buffer is lazily
committed and a Metal `.storageModeShared` buffer is not, which is a factor this ranking does not carry and
§9 item 8 measures.

## A 250 pt timeline cannot hold four layers plus an open band (2026-08-30) — LEFT, deliberately

The bottom row falls off the panel and the artist must drag it taller. **The content scrolls, so
nothing is broken and nothing is lost**, which is why this was recorded rather than fixed, and it was
looked at again on 2026-08-30 and left again. The reasoning, so the next reader does not redo it:

- **The band's height is not the lever.** 96 pt is `TimelineGraphBand.height`, ruled fixed and
  not draggable (KEYFRAMES §11.6, "start fixed"), and shrinking it is the one change that trades a
  legible curve for a visible row — the band is *for* reading a shape.
- **Nor is the panel's.** `timelineHeight` is the artist's own drag and defaults to 250; growing it on
  the band's behalf would take canvas space back without being asked, which
  `AnimationTimeline.timelineHeight`'s own comment rules out in as many words.
- **And auto-scrolling the expanded row into view is not free either.** KEYFRAMES §11.3 measured the
  scroll range a three-layer document has (33 pt against a 96 pt debt) and records that compensating
  the offset moves the reflow onto rows the artist did not touch rather than removing it.

So the honest answer is that a taller stack wants a taller panel, the drag is one gesture, and this
stays a note rather than a fix until the owner says the drag grates.

## The effects menu only exposes its first few items to XCUITest (2026-08-30)

Not a bug in the app, and it will cost a test session. The menu exposes items as far as Gaussian Blur
— Bloom, Sharpen, Sobel, Outline, Chromatic Aberration and Noise never match, on any query. Almost
certainly a scrollable-menu accessibility limit rather than an app defect, but a test reaching for one
of those six will fail to find an element that a human can see, which reads as a broken app. HSV Shift
and Gaussian Blur are the reachable multi-slider fixtures.

## A popover whose host view disappears re-presents itself when the host comes back (2026-08-29)

`CanvasPresentationModifier.close()` (`Views/CanvasPresentationModifier.swift:95-98`) removes the
presentation from the registry and fires the site's `onDismiss` — and **does not write the site's own
`isPresented`**. Reached from `.onChange(of: isPresented)` (`:68`) that is correct, because there the
binding is already false and is what triggered the call. Reached from **`.onDisappear` (`:89`) it is
not**: the host view is being destroyed with the popover still up, `isPresented` is left `true`, and
the next time that host is rendered `.popover(isPresented:)` (`:67`) opens it again with no one having
asked.

The comment at `:84-88` shows the case was thought about from the registry's side — *"without this
line the registry keeps a presentation that is gone and every `onDismiss` bracket in the app leaks"* —
and closed that half. The binding is the half left open.

**It reaches every conditionally-rendered host, not one feature.** The doc names `activePanel = .none`
removing the layer rail as "the everyday way" a host is deleted, so any presentation hanging off a
control that is not always on screen inherits it. Found on 2026-08-29 by the graph editor's channel
list, whose button is rendered only while the band is open: closing the band with the list up, then
reopening the band, brought the list back by itself. That stage shipped a local `onChange` workaround
on its own always-present sibling button rather than change a modifier every presentation in the app
routes through.

**One thing to establish before fixing it, because it decides whether the bug is conditional.**
`.onChange(of: canvasManager.openPresentations.contains(presentation))` at `:81` already writes
`isPresented = false` whenever the registry drops the presentation, which is exactly what `close()`
does one line earlier — so on paper that observer should catch the `onDisappear` path too. It does not
in practice, and the likely reason is that a view being removed from the hierarchy does not get to run
an `onChange` for a mutation made during its own `onDisappear`. **That is inferred from the observed
behaviour, not verified against SwiftUI**, and it is the first thing to check: if the ordering is the
cause, the fix is one line in `close()` and not a rework of the two observers.

## Fill and Clear on a selection rewrite a derived in-between's `VectorCanvas` (2026-08-28)

Every other vector edit that writes a cel's display list refuses on an interpolated cel, because an
in-between's frame is *derived* from its two keyframes and its own `VectorCanvas` is not where the
displayed image comes from. `TopToolbar.swift:143` is the rule stated —
`guard !canvasManager.activeCelIsInBetween else { return }`, with the comment *"the transform would be
written onto a `VectorCanvas` the displayed image does not come from"* — and
`CanvasManager+LassoMove.swift:836` carries the same guard inside `activeVectorMoveTarget()`, so both
lasso and whole-cel Move inherit it.

**`fillSelection` (`SelectionModels.swift:693`) and `clearSelectionPixels` (`:788`) do not have it.**
Their guard chain checks the layer, the cel id and the selection's stamp, and then goes straight to
`vectorCanvas.addFill(...)` / `splitForLassoMove(...)` and the delete. On an in-between that is a write
to a display list nothing renders: the artist taps Fill, sees no change, taps again, and each tap costs
a real undo step. The elements are not lost — they are in the document and they reappear the moment the
cel is committed to a keyframe — which is what makes this quiet rather than loud.

The correct guard is the one its two neighbours already use, and it is one line in each. It was **not
added while building Change Colour (`ed3eab8`)**, nor while rewriting Clear's vector arm to cut at the
loop (2026-08-28), and both times deliberately: changing when Fill and Clear refuse is a behaviour
change nobody has put to the owner, and a new action taking the guard while its two siblings keep the
hole is a smaller inconsistency than fixing two shipped commands on a worker's own judgement. **The
Clear rewrite is the sharper case, because it fixed the same function** — it was asked to make Clear
delete strokes and did exactly that, leaving what Clear *refuses* alone.
`CanvasManager.recolorUnavailableReason` (`:869`) is the shape to copy if the answer is yes — a
sentence in the Select panel rather than a button that goes quietly grey — since a bare
`guard … else { return }` in these two would trade a silent wrong write for a silent no-op.

Not a duplicate of "Canvas Padding while a vector Move is held writes pre-resize geometry onto the
resized cel" below: that one writes correct geometry to the wrong *pose*, this one writes to the wrong
*cel*.

## Every `draw(_:)` view on the timeline track is as wide as the whole document (2026-08-29)

`contentView`, `TimelineRulerView`, every `TimelineRowView`, every `TimelineKeyMarkerBand` and the
graph editor's band are all sized to `totalWidth` — `displayedFrameCount * pixelsPerFrame`
(`Views/TimelineTrackView.swift`, `relayout`). Three of those are `draw(_:)`-backed, so UIKit
allocates a bitmap of that width times the view's height times 4 bytes times the screen scale.

MEASURED as arithmetic, not on device: the 96 pt graph band is **13.8 MB** at 300 frames and the
default 30 pt/frame, **55 MB** at the 120 pt/frame zoom ceiling, and **184 MB** at 1,000 frames by 120.
The 18 pt ruler and the 12 pt marker bands are the same width and cost proportionally less only
because they are shorter.

**INFERRED, and it is the part worth checking before anything is built**: above roughly 8,192 pt of
view width — 16,384 px at scale 2, the Metal texture limit `CALayer` backing stores are subject to —
nothing on the track can be backed at all, the ruler included. A **273-frame document reaches that at
the default zoom**, and PERFORMANCE.md's own note that a real scene is 300 to 1,000 drawn cels puts
the owner's ordinary work past it. Nobody has observed this on the device; it may be that `CALayer`
tiles transparently and there is no cliff, which is exactly why it should be measured before it is
designed around.

**Found by the graph editor's D2 and deliberately not fixed there.** Sizing that one view to the
viewport would have bought a correct band under a ruler that had already failed — the width is a
property of the *track*, it predates the band, and the fix belongs to whatever makes the track's
drawing viewport-relative as a whole. D2 did clip its *sampling* to the visible window, so the band's
per-redraw CPU cost is now O(viewport) regardless of document length; this entry is about the
allocation, which that change does not touch.

## Picking a colour or starting a masked stroke can pay a full CPU composite mid-gesture (2026-08-28)

Found while writing CANVAS_RESIZE.md §6 Q5, and it is independent of that feature — nothing about it
needs a resize to exist, since Canvas Padding already reaches the sizes that trigger it. The "Raising
the canvas maximum reaches a raster-storage cost `CompositorBudget` never bounds" entry already
establishes that TODO item (13) raised the canvas maximum to 16383.

**Two different mechanisms, and they stopped being the same one on 2026-09-01.** The eyedropper is
native-size and deliberately uncapped by `CompositorBudget.affordableSize` — `RenderSizing.native`,
now the only live consumer that takes it, for the correctness reason its own doc comment gives. The
live-mask resolve used to share that exemption by accident and now takes `RenderSizing.liveComposite`,
so it is sized with the sandwich; **its cost falls with the knob and the clamp, but the entry below
still stands**, because what makes it expensive is the backend rather than the size.

1. **The eyedropper falls back to the CPU reference once the document is over the compositor's
   admission gate.** `eyedropperRequest()` (`CanvasManager+Eyedropper.swift:47-52`) composites at
   native canvas size on purpose — a downscaled composite would blend neighbouring pixels into the
   sampled colour, and a wrong colour looks exactly like a right one — so once `peakCompositeTextures
   × canvasBytes` exceeds `CompositorBudget.textureBudgetBytes` (`MetalCompositor.swift:516-525`),
   every tap runs `CoreGraphicsCompositor.composite` instead of Metal (`Compositor.swift:365-366`).
   That entry computes the owner's own crash-scene shape (6 `peakCompositeTextures`) tips
   over the iPad 9's 192 MiB budget at **2896²** — reachable today through Canvas Padding alone, well
   under the new 16383 maximum.

2. **The live-mask preview is on the CPU reference unconditionally, gate or no gate.**
   `MaskResolver.coverage` calls `CoreGraphicsCompositor.composite` directly, once per mask source,
   "whichever backend asked" — a parity decision, not a fallback, so it never touches `MetalCompositor`
   at all (`MaskResolver.swift:9-14`, `:180-181`). `resolveLiveMask` (`CanvasView.swift`) runs it
   once at the start of every stroke on a layer clipped by a non-empty mask (`liveMaskStrokeBegan`),
   before the result is cached. Sizing it with the sandwich reduced this and did not remove it: at
   Full on a document the budget does not clamp, the resolve is the same canvas-sized CPU composite
   it always was.

**The cost, transferred rather than newly measured.** Both call the identical
`CoreGraphicsCompositor.composite`/`.grade` that `Compositor.swift`'s own device table and
`PerfBaselineTests.testEffectCompositeCostOnBothBackends` already measured: **203.3 ms** (iPad 9,
Release, warm, 2048²) for one grading layer in the stack, **7047 ms** (Debug, 4.2M px) for the same
operation off-device. MEASURED for those tests, not for this path directly — the transfer is sound
because it is the same function call, not a resembling one, but no test has timed an actual eyedropper
tap or mask resolve. A mask whose sources include a grading layer pays that cost on every stroke begun
on the layer it clips; an eyedropper tap on a document over the gate pays it on every tap.

Not fixed here — flagged, the same posture as the raster-storage entry just named. A fix means either
budgeting these two consumers too (which contradicts why each is uncapped: correctness for the
eyedropper, backend parity for the mask) or caching further up the call chain; both are
product/architecture decisions outside this document's scope.

## An in-between's interpolation recipe vanishes with no report if it will not decode (2026-08-27)

`ProjectStore.swift:1213` reads a cel's recipe as
`interpolation = try? JSONDecoder().decode(InterpolationRecipe.self, from: data)`. A recipe file that
is **present and damaged** therefore yields nil and the cel loads as an ordinary drawing — the same
silent-drop shape as the four decode entries below, in the one tier that still has it, and it is the
contrast with its own neighbour that makes it worth filing: the vector payload decoded twenty lines
above counts every unreadable element into `ProjectLoadDamage` and logs the file and the cel, so
`SaveDamageGate` can raise a banner before the artist overwrites the good copy. The recipe beside it
says nothing at all, to the log or to the counters, so nothing downstream can mention it.

**The next save makes it permanent.** `writeCel` writes `_interp.json` only `if let recipe =
cel.interpolation`, so a recipe that failed to decode is not merely absent for the session: the
manifest is rewritten without an `interpolationFileName` and the link is gone.

**The missing-file half is correct and is not what this disputes.** The comment three lines above rules
it deliberately — *"the recipe derives content, so losing it costs the link, not the drawing"* — and
that judgement holds. What is wrong is that a file which is present and unreadable takes the identical
path, with no way afterwards to tell damage from a recipe that was never there. The fix is the log line
and the `damage` counter the vector arm already has, not a change of policy.

Found while building TODO item (8), which rewrote the *encode* side of this same function (its `json`
helper no longer swallows encode failures with `try?`) and left the decode alone. Related but distinct
from "Duplicating a cel or a layer drops the in-between's `interpolation` recipe" below, which loses the
same field with the file intact.

## Raising the canvas maximum reaches a raster-storage cost `CompositorBudget` never bounds (2026-08-27)

TODO.md item (13) raised `CanvasSizePickerView.maxDimension` 8192 -> 16383 and let `canvasPaddingRange`
grow to a 1024 base. The item itself asked to check what a 16383² canvas costs before shipping it,
rather than shipping a setting that crashes — this is that check, and the answer splits in two.

**The interactive composite is fine — `CompositorBudget` already covers it, unmodified.**
`CompositorBudget.affordableSize` scales the GPU composite down to `textureBudgetBytes` before it
allocates anything. On the owner's own 3 GB iPad 9 (`textureBudgetBytes(physicalMemory: 3 GB) == 192
MiB`), a 16383² canvas holding the owner's own crash-scene shape (6 live textures,
`peakCompositeTextures`) composites at roughly **2896²** instead of full size — a softer preview, not
a crash. That is the exact mechanism `CompositorBudget`'s own doc comment describes, doing its job on
a canvas four times the pixels of the one it was written against.

**A freshly created canvas — even at 16383² — costs nothing extra by itself.** `RasterLayerTexture` is
lazy: a blank cel has no backing `CGContext` (`context` stays `nil` until the first stamp or a load),
and both `resized(to:offset:)` (the function `setCanvasPadding` calls) and `flipped` check
`hasContent` first and leave a still-blank cel blank and free. `VectorCanvas` stores geometry, not
pixels. So creating a document at the new maximum, or padding one nobody has drawn on, allocates
nothing beyond what it costs today.

**What is not covered: a raster tier that actually holds ink, at or near the new maximum.** The
moment a cel's raster tier is materialized — the first stroke on it, a fill, a bake, or
`setCanvasPadding` resizing a cel that already `hasContent` — it allocates a full canvas-sized
`CGContext`/`UIImage`, with **no budget check of any kind**. `CompositorBudget` bounds the
compositor's own ephemeral scratch textures (`peakCompositeTextures`, the upload cache); it was never
asked about, and says nothing about, the persistent per-cel `raster`/`fillImage`/`bakedImage` tiers
this item makes reachable at a new size. MEASURED: one canvas-sized `rgba8Unorm` buffer at 16383² is
16383×16383×4 ≈ **1.02 GB** — before `fillImage`/`bakedImage` are counted, and before
`setCanvasPadding`'s own doc comment's "at least two canvas-sized images per cel" during a resize
(whose own measurement, 3.5 GB for 32 cels at 2048×1024, scales roughly ×128 with the pixel-count
ratio to 16383²). On the owner's named 3 GB device, with roughly 1.4 GB of headroom before jetsam
(`CompositorBudget`'s own doc comment), one drawn stroke on one raster layer near the new maximum is
already more than the whole process is allowed to hold.

**Not fixed here — flagged instead, per the item's own instruction.** This is a pre-existing gap in
`CompositorBudget`'s scope (it bounds compositor scratch, not document storage), not a defect this
item introduced — but the raise makes it reachable through the UI for the first time at a size where
it matters. Whether the fix is a storage-side budget, a warning at creation time, or an owner ruling
that a near-maximum canvas is understood to be raster-light (vector/text, not painted) is a product
decision, not a one-line change, and is out of scope for item (13) as built.


## A project restored from backup comes back with no strokes (2026-08-27) — NOT A BUG, the test was

**There is no data loss. Nothing in save or in either recovery path was ever broken**, and the framing
this entry carried — "which half is broken, the save or the recovery" — had no true answer. The two
`GalleryRecoveryUITests` failures were the *test* reading the wrong tier, and they could never have
passed.

Both asserted `readLayerStrokeCount(app, layerIndex: 0) == 1`. That helper reads
`layerPanel.row.0`'s value, which `LayerStackListView.swift` fills from
`cel?.raster.strokeCount ?? 0` — **the raster tier**. Layer 0 of a new canvas is a *vector* layer
(`CanvasSizePickerView.createCanvas` calls `addVectorLayer()`), so the drawn stroke is geometry in
the cel's display list and the raster tier reads 0 whatever happened to the project.

**The distinguishing experiment this entry asked for was run, and it answers the other way.** Measured
on a dedicated simulator 2026-08-27, reading both tiers with the stroke drawn and *before any save*:
vector strokes **1**, raster **0**. That single reading eliminates save, both recovery paths and the
round trip at once — the count the assertion wanted was already absent before there was anything to
lose. Every other assertion in both tests already passed: the damaged label clears, the tile relists,
the trash round trip completes, the project reopens.

**Broken by `57c11e6`** ("empty vector layers are free, and vector is the default kind", 2026-08-11),
whose own message says "Ten XCUITests assumed raster". It swept this same file and fixed four other
`readLayerStrokeCount` call sites in it, and missed these two. Before that commit layer 0 was raster
and the assertion passed off `RasterLayerTexture.load(..., strokeCount: 1)`'s default — a
flattened-bitmap heuristic, not a real count, so it was weak evidence even when green.

**Fixed** by reading `readVectorMarker(...)?.strokes`, the exact-count analogue the sibling classes
already use, plus a pre-save assertion in each test so a future failure says which half broke.

**Left open**: `readLayerStrokeCount` silently answers 0 for every vector layer, which is now the
default kind. Two other classes carry comments about catching it during authoring
(`MenuInterruptionUITests.swift:22`, `ToolsAndSelectionUITests.swift:941`); it deserves a loud failure
rather than a plausible number, but rasterize/merge tests legitimately read that tier on a
vector-origin layer, so the guard needs a full-suite run to land safely.


## Move with no selection blocked the brush button (2026-08-27) — FIXED `a506d66`

**FIXED 2026-08-27 by `a506d66`**, and the owner's guess that item (15) would subsume it was half right —
(15) narrows it but the fix is independent and landed first. `selectedTool`'s own `didSet` now closes an
engaged whole-layer Move, which reaches all six writers by construction instead of the four call sites the
brief named. **It could not go in `commitAllInteractiveState()`**: `TopToolbar.toggleMove()` calls that
*before* toggling the flag on every tap, so the close would zero it and the toggle would set it straight
back — Move could never be dismissed from its own button.

**Gated on `Tool.isMomentary` on both sides.** The eyedropper is a round trip the artist experiences as one
tap, so sampling a colour mid-Move must not commit the box; `.text` is deliberately *not* momentary,
because a text session outlives the tap. **A second-order bug was found and fixed inside this work**: the
first draft exempted the transition whenever *either* side was momentary, which also exempted a direct
switch from an armed eyedropper to a real tool and quietly reopened the original defect behind one extra
tap. The agent's own test caught it, not review.

**Reported from the iPad, 2026-08-27.** The owner: *"if I click on move without lassoing first (so a canvas
move), I cant click on a brush."* A whole-canvas Move — Move selected with nothing lassoed — leaves the app
in a state the brush tool cannot be selected out of.

The owner's own read is that TODO item (15) makes it moot: *"since the canvas layer resize thing is going to
be discarded and replaced, I dont think you need it."* **That is a hypothesis, not a finding.** If the block
lives in the whole-layer Move path then (15) removes it; if it lives in the tool-switch arbitration — the
same neighbourhood as `Tool.followsBrushPresetSelection`, `activePanel`, and the commit-before-switching
path — then (15) leaves it standing and it needs its own fix. Settle it by reading before deciding, and note
that it is a live defect on the shipped build either way.

## Canvas Padding while a vector Move is held writes pre-resize geometry onto the resized cel (2026-08-27)

**Found 2026-08-27 by the teardown audit `cf5de83` ran, not reported.** It is pre-existing and that commit
deliberately did not fix it.

`setCanvasPadding` replaces the cel's `VectorCanvas` outright. `resized(to:offset:)` drops the suppression,
so **no ink is lost** — that is the good half, and it is why this is not in the silent-artwork-loss class
its five neighbours were. But a held `vectorFloat` then points at the *old* canvas object, the version
mismatch drives `cancelVectorFloat`, and cancel writes the float's **pre-resize** geometry onto the
**resized** canvas. The artist gets their drawing back at the wrong offset.

The other five doors of the same audit — `rasterizeLayer` (Rasterize and Merge Down), `moveCelToLayer`,
`deleteLayer` and `clearCel` — were each one line and are fixed in `cf5de83` through one helper,
`commitVectorFloatIfLifted(fromLayer:cel:)`, gated on the float's own layer so an edit elsewhere leaves a
float the artist is holding alone. **`deleteLayer` was the subtle one**: `handleActiveContextChanged` does
commit, but the layer is already out of `layers` so the float resolves nothing — and because
`captureStructure` snapshots `layers` while a `VectorCanvas` is a reference type, **undo brought the layer
back with the suppression still live**.

This one is left because it is `setCanvasPadding`'s own coupling rather than a missing commit, and it sits
in TODO item (9) / [CANVAS_RESIZE.md](CANVAS_RESIZE.md) territory — the resize path is being rebuilt there
and a fix written now would be written against the path that is going away.

## Drawing on a scaled-down vector cel silently discarded most of the ink (2026-08-27) — FIXED `cf5de83`

**FIXED 2026-08-27 by `cf5de83`** — TODO item (15) stage 1. Move with no selection now lifts the whole cel
into the lasso float, which bakes into canvas coordinates on commit, so the clipping path is no longer
reachable: `TopToolbar.swift:153` was the only writer that could set `isVectorTransforming`, so the flag
is now permanently false and every consumer of it is dead-but-live, which stage 2 removes. **The entry is
kept, not pruned, because the negative control is the interesting part** — the regression test ships with
the *old* mechanism driven directly inside it, asserting the loss, so the positive half cannot rot into a
vacuous pass and stage 2 has to delete that control deliberately.

**The numbers, measured rather than predicted.** On a 64×64 canvas shrunk 0.3× about ink centred at
(32,32), the surviving band was **[22.4, 41.6]** — samples at 8, 20, 44 and 56 were discarded and only 32
survived. That is the owner's *"a box around the original object"* rendered as data, and it settles the
disagreement with our own prediction in their favour.

**Found by reading while designing [LAYER_TRANSFORM.md](LAYER_TRANSFORM.md), mechanically confirmed by an
independent reviewer, and SEEN ON THE IPAD 2026-08-27.** The owner: *"After I shrink the entire canvas and
put in a line, the line does not bake properly, and only the part of the line in a box around the original
object gets baked. This box is likely the canvas borders after it got shrunk, and I suspect that there is
some kind of compositor or display think hiding the strokes outside."* Live data loss, on the shipped
build. It was the whole case for LAYER_TRANSFORM.md and for TODO item (12), and that case now rests on
evidence rather than on reading.

**Our predicted shape was wrong, the owner's description was exactly right, and the arithmetic now
agrees with them.** We said *"only the top-left quadrant's worth of the stroke survives"*; the owner saw a
box around the **original object** and added *"The only one quarter of it getting shown does not
nessesarely seem the case."* They were right, and the reason is that the prediction assumed a scale about
the **origin** when the Move box scales about the **ink-bbox centre**. The pivot is the midpoint of
`localContentBounds()` (`CanvasView.swift:1541-1542`), `layerTransform(pivot:)` gives
`position = pivot.applying(_transform)` (`VectorLayer.swift:864-871`), so at identity a pure shrink by `k`
is `p ↦ P + k(p − P)`. **The surviving region is therefore the canvas rect scaled by `k` about the
original object's ink-bbox centre** — verbatim the owner's *"a box around the original object … likely the
canvas borders after it got shrunk"*. Any fix or test written against "the top-left quadrant" is written
against the wrong rect.

**Two facts the owner could not see from the outside.** It is **not display-only**: `render()` feeds
`PixelOps.rasterize(cel:)` and therefore thumbnails, merge and export, so the loss is in the document, not
in the view. And the **geometry is not destroyed** — the samples are intact in `_elements` and it is the
rasterizer that drops them, which is why baking the transform recovers the ink rather than losing it.

**THE OWNER RULED AGAINST FIXING IT IN PLACE**: *"I dont think you should try to fix this, as scaling the
entire canvas should transform the objects coordinates in it, not the entire canvas coordinates as per the
new proposed system."* The repair is **TODO item (15)** — Move with no selection becomes a whole-canvas
lasso move, which bakes into canvas coordinates and deletes the path that loses the ink. Do not patch
`render()` or `renderLocalContent`; the entry stays open only until (15) lands.

`renderLocalContent` rasterizes into a context of exactly `size` — `UIGraphicsImageRenderer(size: size,
format: format)`, `VectorLayer.swift:2451` — **in the layer's local space**, and `render()` step 2
(`:2348-2355`) applies `_transform` to the *finished bitmap* afterwards. So local geometry outside
`[0, size]` is clipped **before** the transform is applied.

But `addStroke(canvasSpaceStroke:)` (`:575`) stores `canvasPoint · _transform⁻¹`. On a cel at scale `k`
the visible canvas therefore maps to a local rect **1/k times the extent** — and everything past the
first `size`-worth of it is cropped at render.

- At `k = 0.5`, three quarters of the canvas stores coordinates the renderer crops.
- At the `minimumScale = 0.02` floor (`ObjectTransformFrame.swift:260`), **99.96%**.

**Repro** (the owner's, and it reproduces): vector layer → Move with no selection → shrink → tap away →
draw across the canvas. Only ink inside a box near the shrunk cel's own extent is kept; the rest is
silently discarded.

**Two neighbours found in the same pass**, both also inferred rather than observed:

- **A whole-cel Move that scales *up* is a bitmap magnify, and the doc comment claims the opposite.**
  `setVectorTransform` says "losslessly (the geometry is re-rasterized at the new transform, no
  resolution loss)" (`CanvasManager.swift:331-332`). It is not — `render()` applies the affine to an
  already-rasterized bitmap. [CANVAS_RESIZE.md](CANVAS_RESIZE.md) §2 states the general fact correctly,
  about a canvas resize, and **nobody joined the two**. Two doc comments in this tree contradict each
  other and the wrong one is on the Move path.
- **Interpolation ignores the cel transform entirely.** `interpolationContentProvider` returns raw
  `.vector?.elements` (`CanvasManager+Interpolation.swift:577`) and `registrationPoints(of:)` reads
  `stroke.samples` and `image.transform.position` — all local. Two keyframes with different cel
  transforms are registered and blended **in two different coordinate frames**.

All three are consequences of the same thing: the local space has no bound, so `render()` has to clip to
stay affordable, and the clipping destroys ink. That is the argument LAYER_TRANSFORM.md makes for baking
geometry into canvas space instead. **The clipping is not a bug in `render()` to be fixed there** —
rendering local content at the transform's own resolution means allocating `1/k` times the canvas, which
at the 0.02 floor on an 8192 canvas is 1.7e11 pixels.

## An unclamped zoom-out drag can store a coordinate 100x the canvas extent (2026-08-27)

**This is a prerequisite of TODO item (8), not a curiosity.** `CanvasView.swift:3074-3075`:

```
// No upper bound on zoom; the tiny floor only guards against a pinch's fingers crossing.
committedScale = max(committedScale * liveScale, 0.01)
```

A floor of 0.01 of fit and **no ceiling**, so a screen-wide drag at minimum zoom spans ~100x the canvas
extent: **1,638,400 pt** at the owner's new 16,384 ceiling. Nothing in the tree clamps what gets stored.

Against that, item (8)'s settled field — **16 signed bits an axis at quarter-pixel, ±8,192 pt** — is
**200x short**. Even the 18-bit variant that was briefly settled is 50x short. So **(8) needs a
saturating clamp at encode time**, and the clamp is a decision with a visible consequence (ink drawn far
outside the canvas is truncated at the boundary rather than stored faithfully), not an implementation
detail to be chosen silently.

Note this bound is *independent of* item (12): baking geometry into canvas space removes the layer-local
`1/k` blow-up, but does nothing about zoom. It is also **worse** than the blow-up it replaces —
1,638,400 pt against the 409,600 pt a 2%-scaled layer produces.

## `TextSettingsPanel` grew three presentations the census says it doesn't have (2026-08-27)

Found running `tools/presentation-census.sh` while closing out session 69 — not a report, just the
routine check. It prints **14** unregisterable presentations; `MENU_PRESENTATION_CENSUS.md`'s
"SETTLED SAFE" list names twelve and, at line 119-121, says outright: *"The five panels `SelectPanel`,
`TextSettingsPanel`, `StrokeSettingsPanel`, `MaskTuningSection` and `InterpolatePanel` contain no
presentations at all."* That sentence is now false. Add Text's later stages gave
`TextSettingsPanel.swift` three presentations the census never saw: the font-family `Menu` (`:115`),
the face `Menu` (`:150`), and a stock `ColorPicker` (`:202`).

The two `Menu`s are almost certainly safe by the census's own finding — `MenuInterruptionUITests`
measured that a SwiftUI `Menu`'s dismiss region absorbs the whole touch sequence and never passes a
drag through to the canvas, which is what makes every other `Menu` in the app SAFE rather than
BROKEN. Nobody has run that measurement against these two specifically.

The `ColorPicker` is the more interesting one: it is the first stock `ColorPicker` in the app whose
*parent* is not itself a registered presentation. The other stock `ColorPicker` (`OnionSkinPanel.swift:326`)
sits inside a popover that is a `CanvasPresentation` case (`showOnionSkinOptions`) — a registered,
`isPresented`-bound presentation the census could reason about. `TextSettingsPanel` is reached through
`activePanel` (`DrawingView.swift:399`), the same top-level mechanism the census calls safe for the
*panel's own* teardown (line 114-116) — but the `ColorPicker`'s own system presentation, once it is
open, is a second thing on top of that, with no `isPresented` binding to register and nothing measured
about whether a stroke can start under it the way `.popover` demonstrably could before the 2026-08-20
fix.

Not fixed here — it needs the same kind of measurement `MenuInterruptionUITests` already did for
`Menu`, not a guess.

**Half of this is now done, 2026-08-27.** `MENU_PRESENTATION_CENSUS.md` no longer says the panel
contains no presentations; the correction went in with the change that moved the panel to a bottom bar,
because that change made the sentence's *other* half stale too. What is still open is the measurement,
and moving the panel did not alter it: the `ColorPicker` opened over live canvas from the top-leading
dropdown and opens over live canvas from the bottom bar, so it is the same hazard at a different anchor.
One tap outside it dismissed it and placed no text box, which is worth knowing and is **not** the answer
— `.popover`'s failure mode is a drag, and a tap cannot tell the two apart. The two `Menu`s were spot-
checked the same way and behaved as the census's `Menu` finding predicts.

## A vector cel holding warped text re-warps it on every invalidation, not once per commit (2026-08-26)

Found reviewing ADD_TEXT.md stage 5 and **deliberately not fixed** — the fix is a cache in a budget
§4 rule 6 calls "a cliff, not a slope", which is an owner decision rather than something to slip in
beside a bug fix.

`VectorCanvas.draw(text:into:quality:)`'s `.projective` arm routes through `TextLayout.drawWarped`,
which runs a supersampled CoreText pass and then a **synchronous GPU round-trip** —
`MetalWarpEngine.warp` ends in `waitUntilCompleted` — every time the layer flattens. Not every time
the artist types: a timeline tick, a thumbnail regen, an onion-skin pass. ADD_TEXT.md §4 rule 7 sizes
the warp as "one canvas-sized cost, once, at bake", and that is true of the raster bake and **not**
true here. Rule 4 keeps the *bumps* to two per text session, so what bounds this is how often
something else invalidates the layer. The `.affine` arm has no such cost because it resamples
nothing — it concatenates a matrix and draws glyphs.

The obvious fix is a memo keyed on frame + recipe, and it is not cheap:

- `TextRecipe` and `TextFrame` are `Equatable` but not `Hashable`, so the key is a `Hashable`
  conformance spread across four types (`TextRecipe`, `Typography`, `TextFrame`, `FontDescriptor`)
  rather than a cache line.
- The entry it would hold is a **destination-sized bitmap**. The shared upload cache is 192 MiB and an
  over-budget composite is declined *silently*, dropping the whole cache process-wide.

So the trade is "a synchronous GPU round-trip per flatten" against "another tenant in a budget that
fails silently when it overflows", and it wants a measurement of how often a vector cel with warped
text actually flattens before either side is chosen. The cost is written down at the call site.

## The raster Move box is the one piece of chrome `CanvasTouchOwner` cannot arbitrate by point (2026-08-22)

Found while settling the "one touch, one actor" rule, and deliberately left — it is a gap in the
*model*, and the behaviour it describes is already single-actor by UIKit's own ordering rather than by
the precedence that now settles everything else.

Every other overlay that claims a target has a `CanvasTouchChrome` case, so
`CanvasView.Coordinator.canvasChrome(at:)` can ask it whether *this point* is its, and the five
container recognizers stand down when the answer is yes. `FloatingPieceOverlayView` has none: it is a
single total claim (`CanvasTouchOwner.floatingPiece`) covering the box, its grips and the tap-away
alike, because the view is pinned to the whole container with no `hitTest` override. So the model
cannot distinguish "on the raster Move box" from "anywhere else while a raster piece floats", and
`yieldsToTheOwner` has to answer for the pair.

The visible consequence is one row: a **guide grip that sits under the raster Move box**. The guide
overlay is now fronted above the floating overlay (`updateUIView`'s ordering), so the grip wins and the
piece is not dropped — which is the ruling — but it wins because it is the top view, not because
anything asked the precedence. Nothing double-fires either way.

The fix is to give the raster box a chrome case of its own — a `claimsTouch(at:)` on
`FloatingPieceOverlayView` measured against `piece.transformedBounds`, a sixth
`CanvasTouchChrome`, and a clause in `CanvasTouchOwnerLogicTests.isReachable`. It is half an hour and
it moves the per-pair reachable count, which is why it is written down rather than folded into a
behaviour change.

## Cut is a no-op on screen when the eraser is thinner than the line (2026-08-22)

Found while building Mode 2's live preview, and **not introduced by it** — this is how Mode 2 has
behaved since it was written. Recorded because the preview now shows it honestly, so the artist meets
it directly instead of only after lifting off.

Mode 2 removes the parametric span of a stroke's centreline that lies under the eraser, then hands the
two surviving pieces to `BrushStamper`, which gives every stroke **round end caps**. Each cap reaches
back into the gap by the stroke's own radius. Cut a 40pt line with an 8pt eraser and the two caps meet
in the middle: the display list gains an element and **zero pixels change**. MEASURED —
`VectorCutPreviewLogicTests.testAStrokeThickerThanTheEraserPreviewsTheNothingThatTheCutActuallyTakes`
asserts the pixel delta is exactly 0.

The cut is real and useful — the line is now two strokes that can be moved apart — but nothing on
screen says so. Before the live preview the artist at least saw the same nothing *after* lifting; now
they watch nothing happen for the whole drag, which is a more pointed version of the same question.

**This is an owner decision, not a defect to pick a fix for.** The options are not equivalent:

- Leave it. Cut is a geometry tool; a thin eraser across a thick line is a request the tool answers
  precisely and invisibly.
- Refuse it — a cut whose span is shorter than the stroke's own diameter changes nothing visible, so
  it could be declined, leaving the stroke whole and the eraser feeling like it missed.
- Widen it — grow the span by the stroke's radius so the gap actually opens, at the cost of the cut no
  longer landing where the artist aimed.

Nothing was changed here. The preview reports the current behaviour faithfully, which is the most a
preview should do about it.

## Mode 2's preview draws into a flattened copy, so a crossing stroke flickers (2026-08-22)

The live preview seeds a scratch raster from `VectorCanvas.render()` — a **flattened** image — and
erases the doomed spans out of it. A second stroke whose *ink* overlaps a doomed span, but whose
*centreline* stays outside the eraser, is not cut and keeps all its ink after the lift; in the preview
its overlapping pixels go with the span and come back the moment the finger comes up.

Bounded by construction: the region at risk is the overlap of two strokes inside one eraser footprint.
`VectorCutPreviewLogicTests.testInkThatSurvivesTheCutIsBrieflyErasedFromTheFlattenedPreview` pins it
under 10% of what the cut removes, so a change that made it large would fail rather than be noticed by
somebody drawing.

The exact fix is to re-render the affected strokes instead of drawing into a flat copy, and that is
precisely the term that makes Mode 3 cost ~95 ms a sample (PERFORMANCE.md items 10 and 17). Not worth
it for a flicker on a crossing, unless the owner reports seeing it.

## The mask cache is the one canvas-sized cache with no byte bound (2026-08-20)

Found while reconciling the app's memory budgets for PERFORMANCE.md item 13, and deliberately not
fixed there — recorded because it is the sort of asymmetry that reads as intentional until somebody
works at 4096².

`MaskResolver.cache` is `MaskCache(limit: MaskResolver.cacheEntryLimit)` — **eight entries and no byte
budget of any kind.** Its two siblings both have one, and their own comments say why an entry count
stopped being a bound: `PixelOps.rasterizeCache` carries "the byte budget below is what actually
bounds it; the entry count is kept as a second ceiling for small canvases", and
`CompositorMetalEngine`'s upload cache has `budgetBytes` set per composite. Both learned that from a
measured crash on the owner's iPad.

A coverage buffer is 1 byte per pixel, so the arithmetic is:

| canvas | per entry | 8 entries |
|---|---|---|
| 2048×1024 — the owner's | 2 MiB | **16 MiB** |
| 2048² | 4 MiB | 32 MiB |
| 4096² | 16 MiB | **128 MiB** |

**At the owner's canvas this is not a problem and should not be treated as one** — 16 MiB against
192 MiB apiece for the two caches that do have budgets, which is exactly the eightfold overstatement
PERFORMANCE.md §1 exists to warn about, and §5's "do not tune a budget that never fires" applies. At
4096² it is 128 MiB, two thirds of the whole Metal budget, held by a cache of coverage masks, and it
cannot be capped by anything except being small.

The fix, if a future session works at that size routinely, is the one `PixelOps` already wrote: borrow
`CompositorBudget.textureBudgetBytes` at some fraction and evict on bytes first, count second, never
evicting the entry just stored. It is perhaps fifteen lines. What stopped it here is that choosing the
fraction is unmeasured tuning — `/4` gives three entries at 4096², and whether three is enough for a
frame with several masked layers is not answerable from this side of the owner's document.

## Onion skin at Full pushes canvas-sized sources through the compositor's cache (2026-08-18)

`OnionSkinRasterCache` exists to keep the onion skin's sources *out* of `PixelOps.rasterizeCache`, and
its own doc comment says why: that cache evicts FIFO under a shared byte budget and its entries are
canvas-sized, so "pushing ten small onion entries through it would walk the compositor's current-frame
working set out of it in FIFO order, trading a stall on the onion skin for a stall on the artwork."

**At Full it does exactly that.** `OnionSkinRasterCache.image(for:canvasSize:at:)` opens with

```swift
guard size.width < canvasSize.width || size.height < canvasSize.height else {
    return PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
}
```

and at Full `size == canvasSize`, so every skin falls straight through to the shared cache — not as a
small entry but as a **canvas-sized** one. `OnionSkinBudget.residentCeilingBytes` reports 0 bytes
cached there, which is true and reads as a saving; it is only an accounting fact about which cache
pays.

Two consequences, and the second is the one that costs the artist time:

1. **The onion skin can evict the artwork.** On a 3 GB iPad `CompositorBudget.textureBudgetBytes` is
   192 MiB, so a 4096² document's shared cache holds **three** flattens in total. Ten skins at Full
   walk it clean on every rebuild, and the current frame's own layers are what get walked.
2. **Full's real rebuild cost is roughly half again what the resolution table says.**
   `PerfBaselineTests.testOnionSkinCostOfEachResolutionOption` measured composite cost from
   pre-reduced sources; at Full there is no such thing as a pre-reduced source, and the flatten cannot
   be cached because three slots cannot hold ten skins. Measured 2026-08-18: 1953.8 ms of composite
   plus ten misses at ~104 ms each is **~2.9 s per drawing change**, not 1954 ms.

The owner's own 2048x1024 canvas is unaffected — an 8 MiB entry means the shared cache's 24-entry
limit binds rather than its bytes, so the whole window caches and a rebuild pays one miss. This is a
large-document problem.

**Not fixed here, and the panel's caution is a mitigation rather than the fix.**
`OnionSkinBudget.cachedSourceCount` now models the above and
`OnionSkinBudget.estimatedRebuildMilliseconds` includes the misses, so the panel tells the artist what
Full will cost on their document and names a cheaper setting. That leaves the eviction of the
compositor's working set untouched. The shape of a real fix is to stop taking the shared cache's path
at Full — either give `OnionSkinRasterCache` its own entries at canvas size under its own 64 MiB
budget (correct, but 64 MiB holds one 4096² entry, so it buys almost nothing), or pass
`memoize: false` at Full and accept an uncached flatten per skin (which stops the eviction and makes
the cost honest rather than borrowed). Both are behaviour changes to the render path and neither is
what the owner asked for on 2026-08-18, which is why this is written down instead.

## `validateProject` cannot see a file that is intact but unreadable (2026-08-17)

**This is about the safety net, not a call site, which is what makes it the most valuable of the four
entries below it.** `ProjectBackupManager.validateProject` (`ProjectBackupManager.swift:451`) is what
decides whether a package is damaged — it gates auto-repair at launch (`:137-138`), the gallery's
`isCorrupted` flag (`ProjectStore.swift:44`/`:54`), and the atomic save's refusal to swap a bad stage
over a good package (`ProjectStore.writeAtomically`). It checks that the manifest decodes and that every
file the manifest names **exists**, plus, for PNGs only, that the first 8 bytes are the PNG signature.

The vector JSON is checked for existence alone: `:476` passes `isPNG: false`, and `:463` returns
`true` immediately for anything that is not a PNG. So a vector payload that is present, complete and
syntactically valid JSON — but holds one element this build cannot read — **is "intact" by every test
the safety net applies.** Auto-repair never fires, the gallery shows the project as healthy, and the
save path will happily swap a package built from the degraded load over the good one.

That is exactly how the cel-discarding `try?` fixed on 2026-08-17 stayed invisible: the layer that
exists to catch data damage was structurally incapable of seeing it. The per-element decode now keeps
the loss to one element and `ProjectStore`'s `ProjectLoad` log line says it happened, but nothing
*validates* semantic readability, and the same blind spot covers `manifest.json`'s content (a manifest
that decodes into a nonsense document validates fine) and any future sidecar that is not a PNG.

The shape of a fix, if one is wanted: give `validateProject` a content probe per file type rather than
a magic-number check — decode the vector JSON and the interpolation recipe rather than stat them. That
costs a full parse of every payload in every project at launch, which is why it is written down here
rather than done: it is a real cost/benefit call against a rare failure, not an oversight.

**The product call this left open was answered on 2026-08-21 and is built** — the owner chose *prompt
once, then remember*, and `Services/SaveDamageGate.swift` carries the decision and the reasoning. What
that changes about the entry above: the counts no longer stop at a log line. They travel out of the
decode as `ProjectLoadDamage` on the `CanvasManager`, and the first save the *artist* starts on a
document that lost something raises a banner naming it, with Save Anyway / Cancel. An automatic save
never blocks — it writes a complete package into the project's version history and leaves the project
file untouched — so an unanswered damaged document cannot be overwritten by a backgrounding.

The paragraph this replaces said the loss was "recoverable, not final" because the pre-save stash
keeps the intact original. That is true for five saves. `pruneBackups` keeps
`maxAutosaveBackupsPerProject` (5) `auto-` slots and `refreshLatestSnapshot` overwrites
`latest.paintproj` with the just-saved *degraded* package on every save — so a damaged project opened
and saved six times has no intact copy left anywhere, silently. Surfacing the existing net was
therefore not enough on its own, and the ruling asks while the good copy is still there.

**The blind spot itself is still open and this does not close it.** `validateProject` still cannot see
a payload that is intact-but-unreadable, so auto-repair still never fires on one and the gallery still
shows the project as healthy. The difference is that the *save* no longer proceeds in silence, which
was the half that could destroy work; the shape of a real fix (a content probe per file type) is
unchanged and still costs a full parse of every payload at launch.


## One malformed layer or cel entry fails the whole project open (2026-08-17)

The same shape as the cel-discarding `try?` fixed on 2026-08-17, one level up and **larger in blast
radius**: `ProjectManifest.init(from:)` reads its layers with `try container.decode([LayerManifest]
.self, forKey: .layers)` (`ProjectManifest.swift:77`), and `LayerManifest.init(from:)` reads its cels
the same way (`:323`). Neither is per-element. One malformed entry anywhere in the tree throws, which
takes `loadManifest` (`ProjectStore.swift:78-82`, itself a `try?`) to nil and `load(from:)` to nil —
**every layer, cel, folder and view preset in the project, not just the damaged one.**

Per-*field* tolerance is already thorough here — most keys are `decodeIfPresent` with defaults, and
`ProjectManifest.swift:319-322` / `LayerKind.swift:69` show the team has met this exact failure before
and point-fixed one instance of it: `decodeMigratingEffectLayers` exists because the retired
`"compositing"` kind string would otherwise throw and, in that comment's own words, take the whole
project down with it. What is missing is per-*element* tolerance across the two arrays.

**It is nonetheless less severe than the cel bug was, and the reason is worth recording.** It is not
silent and it is not permanent: `validateProject` fails the package, launch auto-repair restores the
newest intact backup and sends the damaged one to Trash (`ProjectBackupManager.swift:137-138`), the
gallery surfaces it as `isCorrupted` with a recovery affordance rather than hiding it, and `load`
returning nil means there is no `CanvasManager` and therefore nothing that can save over the file. The
artist is told and the data is recoverable. The cel bug had none of those properties.

The fix is the one just applied a level down: decode `[LayerManifest]` and `[CelManifest]` through a
lossy wrapper whose `init(from:)` never throws, so a damaged layer costs that layer. Note the trap
recorded in `VectorCanvasData`: `JSONDecoder`'s unkeyed container advances `currentIndex` only after a
*successful* decode, so a hand-rolled try/catch/continue loop re-reads the failing slot forever — the
wrapper is what makes it terminate. Small and self-contained; deliberately not done in that branch,
which was scoped to the silent path.


## A corrupt raster PNG silently yields a blank cel (2026-08-17)

`ProjectStore.decodeCel` loads a cel's raster as
`UIImage(contentsOfFile: rasterURL.path).map { RasterLayerTexture.load(...) } ?? .empty(size:)`. A
file that is missing, or present but not decodable as an image, gives a blank raster for that cel with
no signal of any kind, and the next save writes the blank over it.

**Two honest qualifications, because they bound how much of this is actually fixable.** First, it is
not fixable per-element the way the vector payload was: a PNG is atomic, so there is no smaller unit
than the whole cel's raster to fall back to. Second, the most likely cause is already covered —
`validateProject`'s PNG-signature check (`ProjectBackupManager.swift:473`, `isPNG: true`) catches a
crash-truncated write and routes the package to auto-repair.

The real gap is narrower than "the raster can vanish": it is that **this path is not even logged.**
The vector payload beside it now reports a missing or unparseable file through
`ProjectStore`'s `ProjectLoad` logger; the raster, whose loss is larger and more visible to the
artist, says nothing at all. A log line here costs nothing and is the whole of the sensible fix.


## One bad swatch loses the artist's entire palette library (2026-08-17)

`Palette.swift:95-101` reads the persisted palettes as
`try? JSONDecoder().decode([Palette].self, from: data)` and falls back to `Self.defaultPresets` when
that returns nil. The array is decoded whole, so **one unreadable palette — or one unreadable swatch
inside one palette — discards every custom palette the artist has built**, silently, replaced by the
seeded presets as though this were a first launch. `save()` then writes the defaults back over the
store at `:204`, and the loss is final.

**This is the same bug that was just fixed for vector cels, in a different file**: an all-or-nothing
decode of an array whose elements are independent, a silent fallback to empty-equivalent, and a
write-back that makes it permanent. Lower stakes than artwork — palettes are cheap to rebuild and this
is not a drawing — but it is still the user's own data, it is still silent, and unlike the project
package there is **no backup layer here at all**: this lives in `UserDefaults` under
`paletteStore.palettes.v1`, which `ProjectBackupManager` does not cover.

The fix is the same one element at a time pattern, and it is smaller here because there is no legacy
shape and no discriminator: decode `[Palette]` through a wrapper whose `init(from:)` cannot throw,
keep the palettes that read, and seed the presets only when *nothing* did. The distinction worth
keeping is between "the store is absent" (a genuine first launch — seed) and "the store is present but
would not decode" (damage — keep what survives and say so).


## The palm baseline that shipped with the snap fix has never run (2026-08-17)

The snap is fixed and confirmed on the owner's device — `requiresExclusiveTouchType` defaults to `YES`,
which closed both snap recognizers to a finger the moment they took the pencil. The mechanism, the
capture that proves it, and the two earlier diagnoses that were wrong are all in commit `7a850c1`;
this entry keeps only the part that is still open.

Turning that flag off means the container's `TouchCountRecognizer` now sees **every** non-pencil
contact during a pencil stroke, a resting hand included. So a palm already on the glass when the shape
formed would snap it unasked. `Coordinator.currentAccompanyingFingers()` guards against that by
subtracting the finger count captured at `beginInteractiveShape` — "how many joined since" rather than
an absolute count — and ratcheting the baseline down so a palm that lifts does not permanently disarm
the snap.

**That guard has never executed.** In the owner's palm-on capture (2026-08-17, build `13:19:37Z`) the
resting hand never arrived as a `UITouch` at all: `base:0` and `counter:1/0` for the whole stroke,
while the deliberate finger at t=5.92 bound correctly and read `stroke:1 joined:1 following:true`. iOS
rejected the palm below our layer, so the behaviour is right for a reason we did not build. The
baseline is insurance whose correctness is argued, not observed.

It matters because the argument has a real edge case in it — the ratchet. A palm that lands *after* the
shape starts following raises the count without raising the baseline, which is indistinguishable from
the deliberate finger. `StrokeGestureRecognizer`'s own count is the source that actually carries the
owner's gesture and needs no baseline, so the failure would be a spurious snap from the container
source, not a missed one.

To close this, a capture is needed in which a palm genuinely reaches the app: a different grip, a
different iPad, or Apple Pencil hover disabled. A capture showing any nonzero `base:` is the first
evidence this code has ever run.

## XCUITest cannot drive the smart-shape hold, so two shape tests are skipped (2026-08-16)

`ShapeHoldClock` decides the hold from `UITouch.timestamp` — the newest sample seen minus the newest
that *moved* — because that is the only clock a main-thread stall cannot fake. Its one assumption is
that a pen held still keeps delivering `touchesMoved`. **On the device that is now confirmed**: the
owner's `ActionRecorder` capture of a 4.4 s stationary pencil hold shows `skipped: 261`, ~59
events/second arriving while the pen never crossed the recorder's 2 pt threshold, with a second touch
in the same file independently agreeing at ~57/s.

**XCUITest's synthetic touch does not, and this is measured rather than inferred.** Instrumenting
`handleStrokeMoved` to publish the clock's own state on `canvas.host` and running
`drawAndHoldShape`'s gesture with `thenHoldForDuration` set to 0.0 s, 1.5 s and 3.0 s:

| hold | samples | pen-clock span | greatest stillness |
|---|---|---|---|
| 0.0 s | 134 | 2.218 s | 0.000 s |
| 1.5 s | 136 | 2.217 s | 0.000 s |
| 3.0 s | 136 | 2.217 s | 0.000 s |

Identical — the drag and only the drag. `thenHoldForDuration` contributes no touch events at all, and
neither does a *leading* `press(forDuration: 3.0)` (92 samples, 1.517 s, the drag again). The clock
never accumulates a single millisecond, so no shape is ever detected and `shape:` stays `none`.

**It cannot be tuned around, and the reason is structural.** XCUITest emits a move only when the
interpolated position changes (a ~0.5 pt quantum: a 1 pt drag at 1 pt/s delivers exactly 2 samples
0.484 s apart, which the app *does* see as 0.484 s of stillness). Within one gesture that spacing is
uniform, and the public API has no multi-segment single-touch gesture — no way to express "travel,
then be still". A drag slow enough to read as still reads as still from its first sample and fires
the hold on a two-point stroke that detects as nothing. Fixing this needs XCTest's private event
synthesis (`XCPointerEventPath` / `XCSynthesizedEventRecord`), which would also give the suite the
two-finger drag `CanvasTransformFreezeUITests` documents as missing — deliberately not attempted here.

**Do not weaken the clock to make these green.** A wall clock cannot tell a parked pen from a frozen
app, which is the bug `ShapeHoldClock` exists to make unrepresentable, and the device data says the
current design is right.

Skipped, both with the reason in their doc comments:

 * `CanvasTransformFreezeUITests.testPinchingWithAPendingShapeMovesTheCanvasAndLeavesTheShapeAlone`
 * `ShapeRecoveryUITests.testDraggingALinesStartHandleMovesThatEndAndLeavesTheOther`

**The second one had two innocent suspects, and it is worth recording that they were cleared.** It
fails on a handle-drag assertion, so it reads like the new anchor maths or the enlarged hit target.
Neither: a line's handles are `.start`/`.end`/`.rotation`, `ShapeOverlayView.anchor(for:)` returns nil
for all three and `report` sends them straight to `onEndpointDragged`, so `ShapeGeometry.canvasAnchor`
is not on that path at all. The anchor maths was separately checked headless (`swiftc`) across five
rotations × both kinds × four corners × four edges, including drags that cross the anchor and flip:
the anchor stays a corner (or axis node) of the result to 1e-4, the dragged handle lands on the touch,
`rotation` is carried through unchanged, and an axis drag leaves the perpendicular extent alone. The
hit target is not it either — `reach` is `22 / canvasScale`, which at the measured `canvasScale`
0.4668 is 47 canvas units against the old fixed 28, and the test grabs the handle dead-on.

The rest of `ShapeRecoveryUITests` still passes, but **not because the hold works**: every one of those
assertions (ink is present, one stroke was recorded, two strokes were recorded) is equally satisfied by
the freehand stroke `drawAndHoldShape` actually leaves. They are not evidence that a shape formed, and
an earlier revision of this entry read them as exactly that.

## A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16)

**One bug, two symptoms, and the eraser is the clean view of it.** With a timeline block menu open,
draw straight through it:

 * *Eraser* — the owner: "it leaves a tiny stroke start. When I try to use the eraser again, it
   disappears and the new eraser stroke is only shown."
 * *Pen* — the same stub, then 0.8 s later a straight line replaces the stroke.

**The 0.8 s is the tell, and it is the owner's own deduction.** It is exactly
`ShapeHoldClock.holdInterval`. What reads as a lag spike is not a stall at all — a separate
measurement puts the popover dismissal at 0.43 ms — it is the stub sitting there while the hold runs
undisturbed to completion, because `handleStrokeMoved` is the only thing that re-arms it and it has
stopped being called. The pen then has shape detection to paint over the evidence; the eraser does
not, so it shows the stub bare.

Two things follow by reading, and together they narrow the mechanism sharply:

 1. **`touchesMoved` stops reaching `StrokeGestureRecognizer`.** Nothing else lets the hold complete
    while the artist is still drawing.
 2. **No terminal callback runs — not `onEnd`, and crucially not `onCancel`.** A lift commits, and
    `handleCancel` rolls the partial stroke back and repaints *inline*; either would clear the stub at
    lift. The stub instead survives the lift and disappears only when the *next* stroke starts, which
    is `beginVectorStroke` rebuilding `vectorScratch` from the untouched canvas — or, equally, the
    next `touchesBegan` finding `trackedTouch` still set and taking `failTrackedStroke`.

So the thing to look for is a path that **stops touch delivery without `touchesCancelled` being
called on the recognizer**. Two candidates reading cannot separate: a view-level
`isUserInteractionEnabled`/removal flip mid-sequence (`reconcileLayers` writes both, and the same
switch is implicated in the Fill entry below), or UIKit dropping the sequence as the popover's
presentation overlay is torn down. Instrumenting the touch lifecycle is what separates them.

**Do not "fix" it by deferring the popover teardown** — that directly reopens the canvas-freeze bug
`CanvasTransformFreezeUITests` pins.

The *line* half is already closed from the other end: the smart-shape hold is now a subtraction
between two `UITouch.timestamp`s (`ShapeHoldClock`), so a stroke whose samples stop arriving can never
complete a hold. That fix stands under both this diagnosis and the dead lag-spike one.

**The stub half is closed as of 2026-08-20, and what is left is the residue.** The product call this
entry left to the owner — whether a cancel caused by *the app's own popover* should throw the artist's
ink away — they made in their 2026-08-18 report, and it is answered by splitting the one abandonment
path in two. `StrokeGiveUp.handedOver` still rolls back, so a two-finger pan begun mid-stroke still
leaves no permanent mark; `StrokeGiveUp.interrupted` commits, with an undo step, exactly as a lift
would have. The stub therefore no longer survives the lift and no longer vanishes when the next stroke
starts. Seven popovers also now close *before* the touch becomes a stroke, centrally
(`CanvasManager.dismissPresentationsOverLiveCanvas()`).

**Two costs remain, both known and both deliberate:**

 * **The stroke is still short.** Closing the presentation a frame earlier does not stop the teardown
   landing mid-sequence; nothing in this app can recover samples UIKit never delivered. The artist gets
   a truncated stroke they can undo or draw over, instead of one that disappears.
 * **The touch that discovers the stranded stroke is spent discovering it.** `touchesBegan` commits the
   corpse and returns, so the *third* attempt is the first that draws, not the second. Binding the new
   touch instead means driving `state` from `.changed`/`.ended` back to `.began`, which is not a
   documented transition and whose failure mode is "drawing stops working" rather than "drawing is
   delayed by one touch". `StrokeInterruptionLogicTests.testTheTouchThatDiscoversACorpseIsSpentDiscoveringIt`
   records it so it stays a known cost.

Still unseparated, and it no longer changes a decision: whether delivery stops because of a view-level
`isUserInteractionEnabled` flip (`reconcileLayers`) or because UIKit drops the sequence as the
presentation's overlay is torn down. Instrumenting the touch lifecycle is what would separate them.

## XCUITests cannot launch into the editor on the iPad 9 (2026-08-16)

The logic tier runs on the owner's device beautifully — 991 tests in 36 s, Release, against 3 min on
the simulator — but **every XCUITest fails in `launchIntoEditor`**, before it has touched anything it
is about to test. 18 of 18 in `SandwichCompositingUITests` + `BlendModesAndCompositorUITests`, all at
the same line.

The trace says why: `Tap "sizePicker.createButton"` → `Computed hit point {-1, -1} after scrolling to
visible`, so the tap never lands and `timeline.frameLabel` never appears. That is the size picker
laying out differently on a 10.2" 4:3 screen (2160x1620) than on the iPad Pro 13" every UI suite was
written against — a test-fixture problem on the device, not a product bug, and nothing to do with the
compositor.

Worth fixing because device runs are 5x faster than the simulator and are the only place the memory
behaviour is real. Likely fix: make `launchIntoEditor` scroll the size picker or dismiss it by
keyboard rather than tapping a button that can land off-screen. Until then, **device testing means
the logic tier only**, and the UI suites stay on the simulator.

## Drawing on a vector layer at 4K was capped at ~19 fps by the live stroke preview — FIXED 2026-08-20

**Kept rather than deleted, and only until the owner has drawn on it.** This file is open issues
only, and the defect is closed on the simulator. What is not closed is the report it came from: the
owner said *17 fps*, and nobody has watched their iPad since the fix. The entry stays as the record
of what to compare against; delete it when they say the canvas draws.

**What it was, MEASURED on the owner's iPad 9 in Release** (`PerfBaselineTests`, now
`testTheLayeredLiveStrokePreviewCostsWhatTheRasterPathCosts`): one dab cost **53.8 ms on a vector
layer at 4096²** against 4.0 ms on a raster layer — a ceiling of **19 fps** before anything else in
the frame, against 250 fps for raster. At 2048² it was 16.4 ms against 3.0 ms. The owner's 17 fps
report was taken at 4096×4096, confirmed by them 2026-08-18.

`StrokeCanvasView.refreshDisplay`'s `.overlay` branch ran once per touch-move and did four
canvas-sized things where the raster path does one: it allocated a **fresh** canvas-sized
`UIGraphicsImageRenderer` bitmap, drew the committed vector render into it, rendered the live scratch,
and drew that over the top. At 4096² the allocation alone is 64 MiB, per dab.

**The fix, as shipped.** `StrokeCanvasView.scratchView` is a sibling `UIImageView` directly above the
base one, so Core Animation composites the live stroke over the committed render — which it was doing
to the flattened result anyway. The allocation and both blits are gone; what is left is
`scratch.renderToUIImage()`, the raster path's own cost. The decision of what goes in which slot is
`VectorPreviewPlan`, extracted so the three `vectorScratchRole` behaviours can be asserted in the
fast tier rather than only by a 22-minute UI suite — and the type has **no case that can express the
old composite**, which is the guard against it coming back.

MEASURED per dab, simulator/CoreGraphics, machine 93.6% idle with no other `xcodebuild` running,
before → after: **8.0 → 2.2 ms** at 2048×1024, **16.1 → 2.5 ms** at 2048², **47.1 → 3.9 ms** at
4096². The raster path costs 2.1 / 2.4 / 3.6 ms at those sizes, so the vector preview now costs what
raster costs. Full table and provenance in [PERFORMANCE.md](PERFORMANCE.md) item 11.

**What remains unknown, and it is the whole reason this is still here.** Every after-figure is the
simulator. The before-figures happen to agree with the device closely on this path (47.1 vs 53.8 at
4096²) because the cost is CPU-side, but *frame rate* is not one cost — it is items 4, 5 and 9(b)
too. **Needs the owner's iPad**: a Release build of this on their 4096² document, and their answer to
"does it still feel like 17 fps?" If it does, the remaining cost is somewhere nobody has looked yet.

**The same trap was on a second path and nobody had looked there either — found by the owner, not by
us, 2026-08-21.** *"Move is extremely slow, reducing FPS to 5fps."* A Move drag on a vector layer was
paying **two** canvas-sized rasterizations plus a multi-megapixel alpha scan per touch-move: 96–108 ms
a sample at the owner's 2048×1024 (MEASURED, Debug simulator), fixed the same way — the live drag now
assigns an affine to the already-rendered layer and rasterizes once on lift. Full provenance in
[PERFORMANCE.md](PERFORMANCE.md) item 16. **The lesson worth carrying is the search, not the fix**:
"canvas-sized allocation per input event" is a *shape*, and it was hiding on a second path that every
area-scaled benchmark in the repo walked straight past. Anything driven by `touchesMoved` on a vector
layer is worth grepping for `render()` before the next owner report arrives.

## The Metal composite hands Core Animation a non-native pixel format (2026-08-16)

`CompositorMetalEngine.readBack` builds its `CGImage` as `premultipliedLast` RGBA in device RGB;
Core Animation's native layout on iOS is BGRA premultiplied-*first*. So assigning one to
`UIImageView.image` costs a full-canvas convert-and-copy inside the CA commit, on the main thread —
three of them per sandwich rebuild, 64 MiB each at 4096². The CoreGraphics backend never paid it: a
`UIGraphicsImageRenderer` image is already in CA's format, so this arrived with the backend flip and
is invisible to every headless benchmark, which stops at the `CGImage`.

**Unmeasured on device** — it is a hitch per stroke-lift rather than a sustained cost, so it is not
the 17 fps above. Worth fixing next: `bgra8Unorm` for the two accumulator textures would produce
byte-identical pixel *values* (Metal presents both formats to a shader as RGBA) with a CA-native
byte order, at the cost of one runtime capability check. Verify with `CompositorParityLogicTests`,
which compares values rather than layouts and so would not itself notice the change.

## Pinch-to-merge in the layer panel measured the wrong axis, and was unreachable (2026-08-22, fixed)

**The owner recorded it on their iPad rather than describing it** — `recording-20260822-120508.jsonl`,
5.5 s, 29 events, pulled over `devicectl`. Open the layers tab, pinch two stacked layers, nothing
happens. The feature exists and is wired correctly: both touches reached
`layerPanel.list`, a `UIPinchGestureRecognizer` is in both touches' `grNames`, and
`LayerStackListView.Coordinator.handlePinch` is attached. It is the **threshold** that is wrong, and
it is wrong structurally rather than by a few percent.

`PinchMergeGate.shouldMerge` fires on `scale < mergeScaleThreshold` (0.6), where `scale` is
`UIPinchGestureRecognizer`'s **radial** distance ratio. The layer list is vertical, and the artist's
gesture is "bring these two stacked rows together" — which is vertical. Measured off the recording,
per sample, in window points:

| t | horizontal gap | vertical gap | radial dist | scale | vertical gap / start |
|---|---|---|---|---|---|
| 2.09 | 137.0 | 89.0 | 163.4 | 1.000 | 1.000 |
| 2.26 | 139.0 | 66.0 | 153.9 | 0.942 | 0.742 |
| 2.29 | 126.5 | 35.0 | 131.3 | 0.803 | 0.393 |
| 2.31 | 124.5 | **10.5** | 124.9 | 0.765 | **0.118** |
| 2.33 | 115.0 | 13.5 | 115.8 | **0.709** | 0.152 |

**The fingers closed 88% of the way vertically and the best scale reached was 0.709 — the threshold is
0.6.** The reason is in the first column: the two fingers were **137 pt apart horizontally** and stayed
115–139 pt apart throughout, because nobody places thumb and forefinger in the same pixel column. That
horizontal term dominates `hypot` and never shrinks, so radial scale has a **floor** at
`dx_final / d_start`.

**That floor is the finding.** Hold `dx` at its observed 137 and set the vertical gap to *zero* — the
fingers meeting exactly — and scale is still `137 / 163.4 = 0.838`. **For this finger placement the
merge could not have fired however hard the owner pinched.** It is not a gesture that is too demanding;
it is a gesture with no reachable success state, and any diagonal placement wide enough relative to the
row height has the same property.

**Fixed by gating on the vertical closure, not the radial scale** — the axis the list actually runs in.
`PinchMergeGate.shouldMerge(startVerticalGap:currentVerticalGap:)` replaces `shouldMerge(scale:)`, and
`gesture.scale` is now read nowhere: `handlePinch`'s `.changed` reads the two live touch y positions via
`location(ofTouch:in:)` and compares their gap against the gap at latch. That baseline needed no new
plumbing — the touch-down y positions were already captured in `pinchTouchStartYs` for `pair(...)`, so
`.began` simply keeps their difference in `pinchStartVerticalGap`. `pair(...)` is unchanged; which rows
latch was never what failed, and the `mergeLossKind` → `pendingMergeConfirmation` route is untouched.

Two conditions, both stored properties so the test asserts the shipped values rather than retyping them:

* **`mergeCloseFraction = 0.45`** — the vertical gap must fall to 45% of what it was at latch. On this
  list's 62 pt rows a pair aimed one finger per row starts 60–90 pt apart, so this asks for 33–50 pt of
  closing: a little over half a row. On the owner's samples it fires at t=2.29, with the fingers still
  35 pt apart — nobody has to make them touch.
* **`minimumVerticalClosure = 20`** — and it must be at least 20 pt of real travel, so two fingers
  merely *resting* on adjacent rows (already only ~62 pt apart) never merge anything on tremor alone.

**Keep the argument above.** The reason a radial term was rejected is not that 0.709 missed 0.6 by a
little, it is the unreachability — and a reader who does not know that will put `hypot` back, because
that is exactly what `UIPinchGestureRecognizer` hands you. Below about 67 pt of horizontal separation
(against an 89 pt starting height) the old rule *was* reachable, which is how a broken feature passed
whatever hand-testing it got; every real hand is well past that.

**The one cost, written down so it is not rediscovered as a bug:** a pair latching less than 20 pt apart
vertically — both fingers within 20 pt of the shared row boundary — cannot fire, since bringing them
into contact is less travel than the floor asks. That is not the same defect as the one it replaces:
there the dead placement (fingers well apart horizontally) was the *natural* one and spreading them
further made it worse, so there was no remedy and no signal; here the dead placement is a deliberately
cramped one whose remedy — start further apart vertically — is what aiming at two different rows already
means. Dropping the floor to remove it would merge layers on a two-finger rest.

The seven samples are the regression fixture, as literals in `PinchMergeGateLogicTests.ownersPinch`:
replaying them merges, replaying them with the vertical motion removed does not, and the old radial rule
(reproduced in the test file only, so its rejection stays documented) fires on neither.

## Two-finger pan/pinch/rotate is dead while the Fill tool is selected, on device (2026-08-15) — CLOSED 2026-08-27, not reproducible

**The owner cannot reproduce it any more and ruled it solved**, 2026-08-27: *"I cant seem to replicate the
freezing bug, so I'll let you know if I ever encounter it again. Chances are the new text UI could have
fixed it, so treat it like its solved. I will bring it up if i ever see it."* That was said of the
**`.text`** half; this Fill entry closes with it because the two were argued to be **one bug** — see the
`.text`-is-this-report's-twin paragraph below, which is the argument, and it is the reason a single answer
settles both. The owner's own guess at the cure, the new text UI, is consistent with that: the bottom-bar
Add Text panel (`e0d5e57`) replaced the presentation the report was taken against.

**Kept rather than deleted, because nothing was diagnosed.** No mechanism was ever found, no fix was ever
written, and the capture that would have named it was never taken. If it returns, everything below is the
investigation to resume — in particular that the two regression nets in `CanvasTransformFreezeUITests`
still pass on the simulator and always did, so a green suite is not evidence the defect is gone.

The original report and the reading that eliminated the obvious hypothesis follow.


The product owner reports it from their iPad: pick Fill and the canvas will not pan, pinch or rotate;
pick any other tool and it does. **Unexplained and not fixed.**

Three simulator attempts failed to reproduce it — including a `-configuration Release` build and a
real two-finger drag rather than the canned `pinch`/`rotate` gestures — and the canvas moved every
time, so this is not something the shipped XCUITests are failing to notice. It may be device-specific
(a real pencil/palm in play, `UIPencilInteraction`, or hover events the simulator never delivers).

Do not "fix" it by guessing at recognizer priorities. **Next step is a capture, not a patch**: turn on
the action recorder (see CLAUDE.md), reproduce it on the iPad, and read which recognizer answered what
— the recording carries every state transition and every `shouldRequireFailureOf` answer, which is
exactly the evidence the simulator refused to produce.

**`.text` is this report's twin, and the pair is the sharpest form of the hypothesis (2026-08-27).**
The owner clarified that report (6)'s *"try to resize the canvas"* meant *"moving the canvas with two
fingers"* — this symptom — reached from the text keyboard. `Tool.paintsOnCanvas` is false for exactly
`.fill`, `.eyedropper` and `.text`, and that is the property `shouldRequireFailure` reads before it
stakes pan/pinch/rotate on anything. So the two device reports name the two *non-momentary* members of
one set, which recasts the question from "what is wrong with Fill" to **"is two-finger transform dead
whenever `paintsOnCanvas` is false?"** — one capture answers it for both. `CanvasTransformFreezeUITests`
now covers the `.text` half beside the `.fill` half; **both pass on the simulator**, which is the same
non-answer the three earlier Fill attempts gave and is further evidence the split is device-only.

**One hypothesis is now eliminated by reading, 2026-08-22, and it was the obvious one.**
`shouldRequireFailure` (`CanvasView.swift`) is the code that can wedge a transform behind a stroke
recognizer — its own comment at the call site says so — so it was the natural suspect. It cannot be
this instance. Its guard requires `activeHost.isUserInteractionEnabled`, which is `shouldInteract`,
which requires `selectedTool.paintsOnCanvas` — and **`Tool.fill.paintsOnCanvas` is false**. So with
Fill selected the guard fails and the function returns `false`: *no failure dependency is stated at
all*, and there is nothing in that state to wedge. Reached independently by two readers before the
`CanvasTouchOwner` refactor and confirmed after it, which changed this line from reading flags
`reconcileLayers` had pushed onto the host to recomputing the predicate live — the right direction for
the *class* of defect, but it does not intersect this instance, and the owner should **not** be asked
to re-test this as a fix check.

Two facts found on the way, worth keeping: **`strokeRecognizer.isEnabled` is read here and assigned
nowhere in the app**, so that third conjunct has always been a no-op defaulting to `true`; and a
staleness race between an input changing and the next `reconcileLayers` pass would be *intermittent*,
where this report is deterministic ("pick Fill and the canvas will not pan"). The capture is now
**more** worth taking than it was, because `shouldRequireFailureOf` records every answer to the
ActionRecorder and that answer is now computed from live state rather than from a flag pushed a pass
earlier — so the `failureRequirement` lines are evidence about the moment of the gesture.

## The mask cache key still cannot see the mask stack's *structure* (2026-08-15, narrowed 2026-08-29)

**The half that shipped.** "A mask sourced from a graded group can be stale" was open here for two
weeks and is **fixed** — `6158e8b`, `MaskResolver.nodeEffects(readBy:of:)` puts the mask stacks' node
grades into the cache key. It was filed as needing an artist edit to bite and was therefore deferred;
KEYFRAMES §2.21's folder tracks made a *keyframe* change that grade on every frame of playback, which
is what forced it. Worth keeping as a shape: a deferred invalidation gap stops being cheap the moment
something animates its input.

**The half that did not.** The key now carries the leaves' content versions and the nodes' grades, but
not the arrangement of the nodes. Two graded nodes **swapping** grades inside one mask source's subtree
leave every version and every `Effect` in the key unchanged, and the mask stays stale. Nothing
frame-varying can cause it — it needs a structural edit, so no playback reaches it — and closing it
means putting the `[RenderNode]` stacks themselves in the key, which is a broader invalidation change
than the pass that found it should have made.

## Whether UIKit honours a `.began -> .failed` transition is unverified, in both directions (2026-08-15)

`StrokeGestureRecognizer.failTrackedStroke` exists to fail a stroke that has already begun, and
**nothing in the suite reaches it.** Every two-finger gesture — synthetic *and* real, confirmed by an
action recording — delivers both touches in a single event, so the recognizer is still `.possible`
and takes the legal `.possible -> .failed` guard instead.

So the question is open on both sides: it is not established that UIKit honours the transition, and it
is not established that it refuses. A defensive conditional readback is in place and is documented in
the code as unproven — do not read its presence as evidence it works.

What would settle it: a test that delivers the second touch in **its own event**, some frames after
the first, so the recognizer is genuinely `.began` when the failure arrives. Until someone writes
that, treat the path as unexercised.

**Update (2026-08-16): the *device* half of this is now reachable, and the reason it was not is the
entry at the top of this file.** A real hand does deliver the second touch in its own event; it was
being dropped before any recognizer saw it, because `isMultipleTouchEnabled` was left at its `false`
default on every canvas view. With that set, a second finger during a *finger* stroke now reaches
`failTrackedStroke` for the first time, and a recording that shows `.cancelled` rather than `.failed`
in the transition line settles the question on the spot. (A finger during a *pencil* stroke does not
reach it — it is refused by type as palm rejection, deliberately.) The suite still cannot reach it,
so the "what would settle it" paragraph above stands for XCUITest.

## Interpolate mode's onion skin is still unmasked (2026-08-17)

The ordinary onion skin's version of this is **fixed**: `Coordinator.updateOnionSkin` now resolves
the current layer's clip through `resolveLiveMask(forLayerAt:)` — the same `CGImage` the compositor's
own mask cache holds, not a second resolution path — and installs it on the onion view's own
`CALayer.mask`, which nothing else owns, so §6.4's slot-collision warning does not apply. Every skin
comes from the current layer, so one mask covers all of them.

`InterpolationReferenceOnionSkinSource` is deliberately left unclipped, and the reason is that there
is no obviously right answer rather than that it was missed. A reference **can span layers**
(VECTOR_INTERPOLATION requirement 5), so the two ghosts it draws are not the current layer's content
and clipping them by the current layer's mask would be wrong for exactly the documents that use the
feature properly. The honest fix is per-reference: resolve each contributing cel's own layer mask and
clip its contribution, which means `InterpolationReferenceOnionSkinSource` growing from "flatten the
reference's cels" into "flatten each cel under its own clip". Small, but it is a change to the
interpolation preview path and not to onion skin.

Severity is genuinely lower than the entry it replaces: this only shows up in interpolate mode, which
is a deliberate mode the artist has entered, on a masked layer, and it is two ghosts rather than up
to ten.

## The multi-pass effect decline path is reasoned-correct and uncovered (2026-08-15)

`EffectPipelines.encode` returns `false` for "declined — fall back to `EffectReference`", and its
caller now honours that with `guard effects.encode(…) else { pool.release(scratch); return false }`.
Nothing tests it: the decline only fires when the device refuses a texture allocation, which a
healthy simulator never does, so the guard is verified by reading rather than by running.

Worth knowing *how* it got there, because the shape recurs. Merging `tmp/p9-layer` and
`tmp/p9-multipass` created it out of two changes git reported no conflict between, because they
touched different lines: `encode` returned `Void` on one branch, so the caller ignoring its result
was correct; the other branch made it `@discardableResult -> Bool`. Merged, the caller discarded the
signal, `@discardableResult` suppressed the warning that would have caught it, and a decline
proceeded to `mix()` with an **unwritten pool texture** — stale pixels presented as a result.

## A green backend-parity test does not prove both backends ran (2026-08-15)

Every parity test appends the Metal case only `if CompositorMetalEngine.shared != nil`, and
`xcresulttool get test-results activities` on a full run shows only Start/Set Up/Tear Down — no
console log, no activity naming the backend. So a green parity sweep is equally consistent with
CoreGraphics-only execution on both sides of the comparison. The tests are honest; their green
under-determines what it exercised. Fix once, generally: an `XCTContext.runActivity` per iteration
recording which backend(s) actually ran.

## Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14)

Both per-cel copy sites build `Cel(...)` without passing `interpolation`:
`CanvasManager+LayerTree.swift`'s `duplicateLayer(at:)` (the `source.cels.map`, ~line 384) and
`CanvasManager+Timeline.swift:106`'s `duplicateCel`. A duplicated in-between therefore keeps its
pixels and silently loses its recipe link — it stops being derived and becomes an ordinary drawing,
with no feedback.

**Deliberately not fixed here, because the obvious fix may be worse than the bug.**
`InterpolationRecipe.references` holds `CelRef(layerID:celID:)` — **UUIDs, not indices within the
layer** — and both duplicate paths mint fresh UUIDs for the copy (and, in `duplicateLayer`, for the
layer too). So copying the recipe across verbatim does not give the duplicate its own keyframes: it
gives it pointers back at the *original's*, and the copy's in-betweens would regenerate from the
source layer, tracking edits to a layer the artist thinks they have left behind. The three candidate
answers — remap each `CelRef` through the old→new id mapping the duplication already builds, drop
the recipe as it does today but say so in the UI, or copy verbatim and accept the shared reference
as intentional — are a vector-interpolation product call, not a layer-compositing one. See
[VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md).

## Fill tool: the gap-closing UI test is still skipped (2026-07-21)

`testFillToolBridgesOpenContourGapWhenGapClosingEnabled` is `XCTSkip`'d. Three separate causes were
found and fixed along the way (an originally unbridgeable gap, `app.sliders.firstMatch` grabbing the
wrong slider, and a synthetic drag too near the screen edge dropping the next stroke) and the final
containment assertion still fails. Next step: re-point the "outside" probe using
`visibleCanvasBounds`/`safeOutsideCornerPoint`. Re-enable by deleting the `throw XCTSkip(...)` at the
top of the test body.

**Its second suggested next step is now the cheap one and the tool for it exists** — this entry used
to say "call `FloodFillEngine.fill` directly on synthetic wall data", which had not been possible for
two reasons: `FloodFillEngine` no longer exists (the fill has been GPU-only since `MetalFillEngine`
replaced it), and `MetalFillEngine.shared` was nil in the test process anyway. Both are fixed as of
2026-08-17: `Fill.metal` is a member of the UI-test target's Sources phase and `MetalFillEngine` asks
for its library by `Bundle(for:)`, so `FillBoundaryLogicTests` drives the real kernels headlessly in
under a second. Telling a genuine leak from a test-probe bug is now a `MetalFillSession.fill` call on
hand-built reference bytes, not a 26-minute run.

## Duplicate rasterizes a vector layer, silently (2026-08-21)

Lasso a region on a **vector** layer, tap Select → Duplicate, and the copy arrives as **pixels on a
new raster layer**. No notice, no confirmation, and the original stays vector so nothing on screen
says what happened until the artist tries to erase or re-cut the copy.

`SelectPanel`'s row calls `canvasManager.beginDuplicate()` directly
(`PaintSoftware/Views/SelectPanel.swift:38`), bypassing `TopToolbar.toggleMove()`'s
`activeLayerIsVector` branch entirely. `beginDuplicate()`
(`PaintSoftware/Models/SelectionModels.swift:261-295`) has no layer-kind check: it runs
`PixelOps.rasterize(cel:canvasSize:)` and `PixelOps.maskedPiece`, then inserts a `Layer` whose cel is
`.empty(size:)` raster (`:279-282`), and `commitFloatingPieceIfNeeded`'s `.duplicate` arm lands the
result through `registerUndoableLayerInsertion` (`:346-348`).

Its two neighbours in the same file already branch correctly — `fillSelection` at `:363` and
`clearSelectionPixels` at `:393` both check `layers[currentLayerIndex].kind == .vector` and keep the
result vector. Duplicate and Move are the two that do not; **Move is being addressed by
[LASSO_MOVE.md](LASSO_MOVE.md) and Duplicate deliberately is not**, so this entry is where it lives.

Found while scoping LASSO_MOVE.md, not by a test — no test draws on a vector layer and then taps
Duplicate, which is also why it has survived. The fix is either a vector arm that copies the lassoed
*elements* onto a new vector layer (LASSO_MOVE.md §1 already specifies how to partition strokes and
fills against a lasso, so most of the design is written), or — at minimum — the same
`.needsRasterization` warning `CanvasManager+BlockDrag`'s cel-drop verdict already raises for the
equivalent timeline case. Guessing between them is a product call.

## Duplicate is a silent no-op against an adjacent neighbour (2026-07-28)

The overlap bug behind this is fixed (the shared frame-length clamp filters `>= startFrame`), but
when a neighbour starts at exactly the source's end frame there is zero free space, so Duplicate
correctly does nothing — with no feedback at all. Worth greying the control out when
`clampedCelLength` returns nil. The alternatives that aren't a no-op — place the copy at the next
free run, or shift later cels rightward — are timeline feature design and a separate decision.

## Switching brush presets resets live size/opacity (2026-07-22)

`selectBrush` re-baselines `brushSize`/`brushOpacity` from the preset, so re-tapping the current
brush throws away a size the user just dialled in. Partly intentional per its doc comment — needs a
product call, not just a fix.

## A folder's key markers are drawn but cannot be asserted (2026-08-29)

`TimelineFolderRowView` sets `isAccessibilityElement = true` on itself, which promotes the whole row to
one element and takes its children out of the accessibility tree. One of those children is its
`TimelineKeyMarkerBand`, which publishes `timeline.folderTrack.<name>.keys` with an encoded
`accessibilityValue` — **and no XCUITest can read it**, because the element it is on is not in the tree.

Layer rows are unaffected: `TimelineRowView` is not an accessibility element, so
`timeline.keyMarkers.<layerIndex>` is queryable and is what the cel-menu UI test reads.

So a folder's grade animates (§2.21), its keyframes draw, and the only assertion that could catch them
regressing is unreachable. That is the same species as *"a green backend-parity test does not prove both
backends ran"* above — the suite is silent about the folder arm rather than green about it, and silence
reads as coverage.

The fix is one line in the wrong place: dropping `isAccessibilityElement` on the folder row would put its
markers back in the tree, and would also put everything else in that row back in — which is a change to a
shipped row's accessibility shape and wants its own branch, not a ride-along. Found while adding the cel
menu's keyframe items, and deliberately not fixed there.

## Missing / stubbed, as designed

- Distort/Warp transform modes render and gesture identically to Uniform but still appear in the Move
  bottom-bar picker.
- Adjust panel and ActionsMenu's Cut/Copy/Paste/Drawing Guide are "Coming soon"; the timeline block
  menu's "Select Multiple" is permanently disabled.
- No UI to change `fps` (fixed at 24) or edit scene length directly.
- Square/custom brushes are tiled round dabs, not true shaped stamps (scalloped edges, seam
  build-up); per-stamp `.normal` compositing builds opacity up where a stroke crosses itself, which
  is the flow-versus-opacity distinction the engine does not make.
  **The "slow strokes read darker than fast ones" half of this entry was wrong and is corrected**:
  dab emission is not timed. `BrushStamper.advance` walks from the last *dab* and returns unmoved
  below one spacing, so a pencil held still lays one dab, and a 400pt line gets the same 50 dabs per
  100pt whether it takes 0.3 s or 10 s. What is left is hand tremor, not the clock — at a slow speed
  the aim from the last dab to the sample that finally clears the spacing carries proportionally more
  noise, so the chain wanders: 100.0 → 106.0 dabs per 100pt from 800 to 40 pt/s at 0.4pt of tremor,
  100.5 → 149.2 at a shaky 0.8pt. `StrokeSampleGate` halves the residue as a side effect. Removing it
  outright is a stabilizer question, not a sampling one.

## Cleanup opportunities

- **Duplicated transform-overlay code — half converged, 2026-08-21.** `ObjectTransformOverlayView` is
  now `TextTransformOverlayView`'s pattern: screen-point chrome divided by `canvasScale`, raw touches,
  nearest-within-reach hit testing, and its geometry on a model type (`ObjectTransformFrame`) where
  `ObjectTransformLogicTests` can reach it. **`FloatingPieceOverlayView` is the last user of
  `TransformHandleView`/`TransformOverlayView` and still carries the fixed 24×24**, which is the same
  defect the owner reported on the Move box on 2026-08-21 — "the move nodes' size doesn't stay
  constant to the screen, and right now they don't seem to respond to touch". It is the raster Move
  tool's floating piece, so it is a different gesture on a different tier and was deliberately left
  for its own branch rather than converted alongside; one gesture-sensitive overlay at a time.
  `ObjectTransformFrame`/`ObjectTransformDrag` are the shape to copy, and the drag arithmetic is
  nearly the same — `FloatingTransform` adds independent axes and flip flags, which is the one real
  difference.
- **Duplicated canvas-flip geometry** — `CanvasManager.flippedImage` and `RasterLayerTexture.flipped`
  implement the same mirror-about-centre draw twice.
- **`ContentView.saveIfNeeded`** fires only on scene-phase change and Return-to-Gallery, so a direct
  project→project transition would silently drop unsaved work. Currently safe only because every
  entry point goes through the gallery first.
- **A vector cel still carries `fillImage`/`bakedImage`**, so raster features allocate canvas-sized
  bitmaps on a vector layer. The product owner wants vector fully divorced from raster —
  [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md) §4 item 26 is the full write-up.
