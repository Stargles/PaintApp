# Known Issues

Open items only — fixed entries are pruned, and the fix lives in the commit and the code comment.
One section per bug, newest first.


## One app switch fires three full saves, and one of them lands on the way back in (2026-08-18)

**This is the owner's "returning from another app freezes for a few seconds", and the owner's own
answer is what settled it.** Asked on 2026-08-18 whether the app comes back where they left it or on
the Gallery, they said *"Exactly where I left off. It only freezes for a few seconds though, which
honestly is to be expected unless something bad is going on in the backend."* There is no
`@SceneStorage` anywhere and `ContentView.screen` is plain `@State` (`ContentView.swift:10-11`), so a
genuine relaunch provably resets to the Gallery. Coming back in place means **the process was never
killed** — jetsam is ruled out, and what is left is the app's own main-thread work.

`ContentView.swift:30-34` guards the save on `newPhase == .inactive || newPhase == .background` and
never looks at where the transition came *from*:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .inactive || newPhase == .background {
        saveIfNeeded()
    }
}
```

SwiftUI passes through `.inactive` on **both** legs, so one background round trip fires three times —
active→inactive, inactive→background, and background→inactive on the way back, that last one while
the artist is looking at the screen. `onChange(of:)` already hands both values; comparing `oldPhase`
is the whole fix.

**Each of those three is a full save, and "IfNeeded" does not mean what it looks like.**
`saveIfNeeded` (`ContentView.swift:56-68`) has no dirty check of any kind — the guard is on the
*screen*, not on whether anything changed. So every one of the three builds a `SaveSnapshot`
synchronously on `@MainActor` (`ProjectStore.swift:205`, constructed at `:295`), which composites the
**whole canvas** to produce a 320×320 tile (`:261-265`) — 2 M pixels for 102 k at 2048×1024 — and
does it *before* `beginBackgroundTask` is requested at `:303`, then enqueues a full-document PNG
re-encode behind it. Three of those compete for the A13's cores per switch.

Mechanism READ-confirmed; the multi-second magnitude is INFERRED, and corroborated by the owner
reporting the symptom. The fix and its verification are [PERFORMANCE.md](PERFORMANCE.md) item 1: a
pure `shouldSave(from:to:)` predicate, testable headlessly.

**Not the same thing as the `ContentView.saveIfNeeded` note under Cleanup opportunities below**,
which is about a save that *fails* to fire on a direct project→project transition. These are the two
opposite failures of the same undirected guard.


## `MaskResolver.clearCache()` says it handles a memory warning and is wired to nothing (2026-08-18)

`MaskResolver.swift:133-135`:

```swift
/// Drops every resolved mask. For tests that need to measure an uncached resolution, and for a
/// memory warning — nothing here is state, so throwing it away only costs time.
static func clearCache() { cache.removeAll() }
```

**Every call site in the repo is a test** — `ValueLayerLogicTests`, `EffectLayerLogicTests`,
`MaskParityLogicTests`, `PerfBaselineTests`, and nothing in `PaintSoftware/`. The app contains
exactly two `NotificationCenter.addObserver` calls (`MetalCompositor.swift:386`,
`PixelOps.swift:150`) and neither is this one. So a memory warning reaches the Metal caches and the
flatten memo and steps around the mask cache entirely, while the doc comment says otherwise.

**This is the identical bug class that `PixelOps.swift:145-149` records having already been found and
fixed once**, in a comment that opens "Nothing dropped these before" and explains that the doc
comment there said "and for a memory warning" while no code anywhere subscribed. Two instances of the
same defect from the same cause — a doc comment describing an intent nobody wired — is a pattern, and
the fix is one `addObserver` block copied verbatim from the file that already got it right.

**The bytes are small and that is not the point.** At 2048×1024 a resolved mask is 1 byte per pixel,
so 8 entries is ≤16 MiB (INFERRED); the ≤128 MiB figure that makes this look urgent is 4096²
arithmetic. `ResolvedMask` is fully re-derivable, so the change is correctness-neutral. Its value is
closing a documented lie before a third instance of it appears. [PERFORMANCE.md](PERFORMANCE.md)
item 6.

Distinct from "A mask sourced from a graded group can be stale" below, which is about the cache
*key*; this is about the cache never being dropped.


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
over a good package (`ProjectStore.swift:336`). It checks that the manifest decodes and that every
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

**The product call this leaves open, which is the owner's and not an engineering one.** A load that
dropped something now continues and saves normally, so the next save writes the degraded document over
the good one. `ProjectBackupManager` stashes the pre-save package on **every** save
(`ProjectStore.writeAtomically` → `stashLiveProjectForSave`), so the intact original does survive and
is restorable — the loss is recoverable, not final. The question is whether that is enough, or whether
a partial load should refuse to overwrite, save under a new name, or prompt before the first save.
Each of those changes save semantics for every project, not just damaged ones, which is why the fix
deliberately stopped at recording the counts (`VectorCanvasData.DecodeReport`) and logging them.


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

`ProjectStore.swift:581-582` loads a cel's raster as
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
`CanvasTransformFreezeUITests` pins; see `AnimationTimeline`'s comment there.

The *line* half is already closed from the other end: the smart-shape hold is now a subtraction
between two `UITouch.timestamp`s (`ShapeHoldClock`), so a stroke whose samples stop arriving can never
complete a hold. That fix stands under both this diagnosis and the dead lag-spike one, but it only
suppresses the line — the stub itself is untouched and the pen would stub silently like the eraser.

Underneath sits a product call, not an engineering one: `handleCancel` discards a partial stroke on
purpose — "as far as the document is concerned this stroke never happened" — because that is what
stops a two-finger pan begun mid-stroke from leaving a permanent, un-undoable mark. Whether a cancel
caused by *the app's own popover* should also throw the artist's ink away is the owner's decision, and
committing it instead would reopen the pan case. Not changed unilaterally.

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

## Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16)

**Measured on the owner's iPad 9, Release** (`PerfBaselineTests.testTheLiveStrokePreviewCostsFourTimesMoreOnAVectorLayerThanARaster`):
one dab costs **53.8 ms on a vector layer at 4096²** against 4.0 ms on a raster layer — a ceiling of
**19 fps** before anything else in the frame, against 250 fps for raster. At 2048² it is 16.4 ms
against 3.0 ms.

**The owner reports 17 fps, and that report was taken at 4096×4096** — confirmed by them on
2026-08-18, and worth pinning here because this entry did not say so and the omission cost real
work. It matches the measured ceiling on that canvas, so there is nothing left to explain: fitting
`fixed + k·area` through the two points above gives ~10.2 ms/dab at the owner's usual 2048×1024, and
the area model holds. See [PERFORMANCE.md](PERFORMANCE.md) §1 — a figure without its canvas is not a
figure in this repo.

`StrokeCanvasView.refreshDisplay`'s `.overlay` branch runs once per touch-move and does four
canvas-sized things where the raster path does one: it allocates a **fresh** canvas-sized
`UIGraphicsImageRenderer` bitmap, draws the committed vector render into it, renders the live scratch,
and draws that over the top. At 4096² the allocation alone is 64 MiB, per dab.

**This is not the compositor and it is not this branch.** No composite runs during a dab —
`makeSandwichKey` freezes the active layer's content version for the duration of a stroke precisely so
the compositor stays off the drawing path — and `refreshDisplay` predates the Metal work. The owner's
own experiment proves it from the other side: halving `renderResolution` cuts a sandwich rebuild from
40.6 ms to 13.1 ms on that device and **changed the frame rate not at all**, because
`RenderResolution` is applied in `makeSandwichRequests` and reaches nothing on this path.

**The fix, and it belongs in its own branch.** Stop compositing the two into one bitmap: give the
scratch its own `UIImageView`/`CALayer` over the committed one and let Core Animation composite them,
which it is doing anyway. That deletes the per-dab allocation and both blits, leaving only
`scratch.renderToUIImage()` — the raster path's cost. It is a change to the most gesture-sensitive
code in the app (`vectorScratchRole` has three modes and `.replacement` and `.none` behave
differently), so it wants its own branch and its own pass through the vector-eraser UI suites, not a
rider on a compositor-memory fix.

## The project thumbnail composites the whole canvas to make a 320x320 tile (2026-08-16)

`ProjectStore.SaveSnapshot` builds a full `makeRenderRequest` at native canvas size, composites it,
and hands the result to `ThumbnailRenderer.render(…, thumbnailSize: 320x320)`. On a 4096² document
that is 16.8M pixels rendered to fill 102k — and on a 3 GB device the GPU path declines it
(`CompositorBudget`, which sizes only the *live canvas* down), so it lands on the CoreGraphics
reference. With a bloom and a blur in the stack that is minutes of background CPU per save.

**Not a regression from the Metal flip** — with the old `.coreGraphics` default the thumbnail took
exactly the same path — and on a device with room it is now much faster than it was. Left alone here
because fixing it properly means deciding what size a thumbnail composite should be and checking that
against `ProjectSaveLogicTests`, which is a save-path change and not a crash fix. The shape of the
fix: give `makeRenderRequest` an optional render size the way `makeSandwichRequests` has one, and
have `ProjectStore` ask for something near the tile's own size.

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

## Two-finger pan/pinch/rotate is dead while the Fill tool is selected, on device (2026-08-15)

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

## A mask sourced from a graded group can be stale (2026-08-15)

A group used as a mask **source** whose effect reshapes coverage — blur, outline, bloom, Sobel,
sharpen — can serve a mask computed before the grade changed.

`MaskResolver`'s cache key is built per-*layer*, from `stack.leafLayerIndices`, and a folder is not a
leaf: a folder's grade cannot reach the key at all, so changing it does not invalidate anything. Only
effects that change *coverage* show it; a grade that only moves colour leaves the thresholded alpha
where it was.

Fixing it means putting node grades into the mask cache key, which is a change of its own and not an
extension of the per-layer version — the key would have to walk the stack's folders as well as its
leaves. Deliberately not attempted alongside the effect UI.

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

## A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17)

Found while closing out this branch, and it narrows the claim `b100cd2`'s successor commit makes
about itself ("on a raster layer it does — the fill flattens into `Cel.raster`, so a line inside the
loop is covered"). That is true of the *flood region* — `LassoFillLogicTests` genuinely proves the
mask covers a line's pixels — but the region becoming `fillImage` is not the same as the artist
seeing the line disappear, and for content already on the *same* cel, it does not.

`Cel.raster` is documented as "Live brush strokes" (`Cel.swift:9`) and `fillImage` as "composited
**underneath** `bakedImage` and `raster`'s strokes" (`Cel.swift:10-11`) — `fillImage` is the bottom
tier, always. `PixelOps.rasterizeUncached` draws it first and `cel.raster`'s strokes last
(`PixelOps.swift:209-211`), and `commitInteractiveFill`'s raster branch reproduces the identical
order when it flattens: `compositeOver(base: fillGestureBaseBaked, overlay: preview)` then
`compositeOver(base: belowStrokes, overlay: cel.raster.renderToUIImage())`
(`CanvasManager+Fill.swift:254-255`) — the pre-existing strokes are the last thing drawn, both for
the live preview and for the flattened result the commit writes back as the new `raster`. Later
draws sit on top in Core Graphics; nothing between `beginInteractiveLassoFill` and
`commitInteractiveFill` erases or clips `cel.raster` in the loop's interior. So a line drawn in an
earlier gesture on the *same* raster layer stays exactly where it was, painted over nothing, on top
of the new fill — same visible outcome as the vector entry below, different mechanism.

**Verified by reproducing the two draw calls above in isolation** (a minimal CoreGraphics
"draw black square, then draw red square on top, sample the center pixel" script matching
`commitInteractiveFill`'s exact sequence) rather than by running the full gesture through
`CanvasManager` — the result is unambiguous (the square drawn last wins every pixel it covers) and
this is standard Core Graphics compositing, not something that needs the simulator to confirm. **Not
run through the actual app** on a real stroke + lasso fill, so treat the general shape as solid and
the exact pixel boundary as unconfirmed.

This is likely why the shipped suite doesn't catch it: `LassoFillLogicTests` asserts only on the
flood session's own `region` bytes (i.e. `fillImage`'s content before it's composited with anything
else), and no XCUITest draws a stroke and then lasso-fills over it on the same layer. The common
coloring-book workflow — line art on a reference layer above a separate colour layer — never hits
this: the "line" being painted around lives on a different cel entirely, so the same-layer tier order
is irrelevant to what the artist sees there. It is specifically same-cel content — the case this
entry's title names — that the tier order defeats.

## A lasso fill does not paint over line art on a *vector* layer (2026-08-17)

The lasso fill type's defining behaviour is the owner's own: "all inner lines are filled over". On a
raster layer it does — the fill flattens into `Cel.raster`, so a line inside the loop is covered.
**On a vector layer it cannot, and the reason is the element ordering, not the fill.**
`VectorCanvas.Kind` is `fill = 0, image = 1, stroke = 2` (`VectorLayer.swift:349`) and
`insertionIndex(forKind:)` keeps the array in that order, so every fill renders *beneath* every
stroke. A lasso fill on a vector layer therefore lands correctly, is the right shape, and the line
art draws straight back over it. The artist sees the compartments filled and the dividing line still
there — the one thing the tool exists to avoid.

**Read from the code, not measured** — the ordering is explicit enough that a test would only confirm
it, but no test in the suite asserts it either way, so treat it as unverified until one does.

Not fixed here because the fix is a change to `VectorCanvas`'s ordering contract, not to the fill:
either a per-fill "draws above strokes" flag (which makes `Kind` no longer a total order and touches
`splicing`, the codable shape and every render path), or an explicit z-order per element. Both are
vector-layer architecture decisions. The narrower alternative — have a vector-layer lasso fill also
*cut* the strokes it covers, the way the vector eraser does — is destructive in a tier whose whole
point is that it is not, and would need the owner's say-so.

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

- **Duplicated transform-overlay code** — `ObjectTransformOverlayView` and `FloatingPieceOverlayView`
  each define their own `HandleView` and near-identical project/rotate/resize logic.
- **Duplicated canvas-flip geometry** — `CanvasManager.flippedImage` and `RasterLayerTexture.flipped`
  implement the same mirror-about-centre draw twice.
- **`ContentView.saveIfNeeded`** fires only on scene-phase change and Return-to-Gallery, so a direct
  project→project transition would silently drop unsaved work. Currently safe only because every
  entry point goes through the gallery first.
- **A vector cel still carries `fillImage`/`bakedImage`**, so raster features allocate canvas-sized
  bitmaps on a vector layer. The product owner wants vector fully divorced from raster —
  [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md) §4 item 26 is the full write-up.
