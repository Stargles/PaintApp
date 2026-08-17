# Known Issues

Open items only — fixed entries are pruned, and the fix lives in the commit and the code comment.
One section per bug, newest first.

## A second touch in a later event was never delivered to any recognizer (2026-08-16)

**Not open as a diagnosis — the owner's capture settles what was happening. Open as a fix that has not
yet been confirmed on device.** Two rounds of wrong guesses preceded it and both are worth keeping,
because each was a plausible reading of a real symptom.

The gesture: keep the pen down on a smart shape, add a finger, the shape snaps. It has never worked.

**Round one** blamed the predicate. `canvasTouchesChanged` gated on an undifferentiated `count >= 2`,
so the fix split `TouchCountRecognizer`'s count by `UITouch.type` on the hypothesis that "the pencil's
`UITouch` is not delivered to a container-level recognizer". It changed nothing on device, and the
owner's 20:31 hold capture falsifies the hypothesis outright: with the pen the only contact on the
glass, `canvas.pan`, `canvas.pinch` and `canvas.rotation` are each asked `shouldRequireFailureOf` and
each go `possible -> failed`, which they cannot do without having received that touch.

**Round two** added a second source — `StrokeGestureRecognizer.onAccompanyingFingersChanged`, reading
the finger off the recognizer the pen is already driving — and instrumented both. The 22:14 capture
came back with the third branch of its own decision table:

```
t=2.55  note   shapeHold fired after 1356.0pt, 416 samples, 0.82s still on the pen's clock -> oval
t=2.56  model  shape.touches = "counter:1/0 stroke:0 following:true"
t=2.96  touch  began  type=direct  touch=2  down=2  hitClass=StrokeCanvasView  depth=3  via=view
t=4.29  touch  ended  type=pencil  touch=1
t=4.31  model  shape.touches = "counter:0/0 stroke:0 following:true"
```

Three `shape.touches` lines in the file and **none at 2.96**. The finger reaches `UIWindow.sendEvent`,
hit-tests onto `StrokeCanvasView` at the same depth the pencil reports, and reaches **no gesture
recognizer anywhere in the chain** — neither the one on that very view nor the counter four views up.
No per-recognizer logic can explain silence in two recognizers with different views and different
delegates. (The capture also confirms `ShapeHoldClock` on real hardware: 0.82 s of genuine stillness
out of 416 pencil samples, which is exactly what XCUITest cannot reproduce.)

**The three per-recognizer suspects are cleared by reading, which is what leaves a view-level cause.**
No delegate declined the touch: `gestureRecognizer(_:shouldReceive:)` is implemented exactly once in
the app, on `TimelineTrackView`, and `StrokeGestureRecognizer` has no delegate at all. No delivery
flag suppressed it: `TouchCountRecognizer` sets `cancelsTouchesInView`, `delaysTouchesBegan` and
`delaysTouchesEnded` all to `false` in its own `init`, and `cancelsTouchesInView` only ever affects
the responder path anyway. There is also no overridable "should I ignore this touch" to inspect — the
decision is private; only the resulting `ignore(_:for:)` is a subclass hook, and both recognizers now
record it.

**The cause is `UIView.isMultipleTouchEnabled`, which defaults to `false` and was never set.** "The
view receives only the first touch event in a multitouch sequence" — a second touch arriving in a
*later* event, while the first is still down, is the case that default drops. It fits everything
else, too, which is what makes it more than a plausible story:

 * Two-finger pan/pinch/rotate work, and this file already records why: both touches of a real
   two-finger gesture arrive **in a single event**, confirmed by an earlier action recording. One
   event is the one event the default allows.
 * `StrokeGestureRecognizer.failTrackedStroke` has never been reached in this repo — see the entry
   below, which notes it is only reachable "when a second touch lands in a *later* event than the
   first, which is what a real hand does and what no test here produces". A real hand did it, twice,
   and it still was not reached, because the touch was not delivered.

The one observation that cuts the other way is worth stating rather than hiding: if a staggered second
touch is always dropped, two-finger pan should fail whenever a hand's fingers land a frame apart, and
it does not. The reconciliation is that they *don't* land a frame apart — a deliberate two-finger
gesture puts both down inside one event, which is the measurement this file already records — whereas
the snap's finger arrives **0.4 s** after the pen in the capture above. Same rule, opposite side of it.
That is consistent, not proven, and `gr` on the next capture is what turns it into one or the other.

The flag is now set on every view a canvas touch hit-tests into: `CanvasHostView`, the canvas
container, `LayerHostView`, `StrokeCanvasView`. None of them implement `touchesBegan`, so nothing
changes on the responder path; only recognizer delivery does.

**Two behaviours change with it, and one of them had to be handled in the same commit.**

 1. *Palm rejection stops being accidental.* A palm landing mid-stroke used to be discarded by UIKit
    before we saw it. It arrives now, and `failTrackedStroke` would discard the artist's stroke with
    no undo step. `touchesBegan` therefore refuses it **by type**: a finger cannot interrupt a pencil
    stroke. A second pencil still can (a different pen, not a palm), and a finger can still interrupt
    a *finger* stroke, which is the one-finger-drag-becomes-two-finger-pan handoff this class was
    written around. That handoff has in fact never worked either, for the same reason, so it starts
    working here for the first time.
 2. *`.began -> .failed` becomes reachable*, which the entry further down flags as unverified in both
    directions. The defensive readback in `failTrackedStroke` is finally on a live path, and a
    recording that shows `.cancelled` there instead of `.failed` settles that open question on the
    spot.

**Unconfirmed until the owner tests it**, and two things to watch in that build:

 * A **resting palm** is a finger to UIKit and the container counter counts any finger, so a palm
   already on the glass when a shape forms could now snap it unasked. The stroke-recognizer source
   does not have this problem — it only counts fingers that arrive *while* a shape is following,
   which is the gesture as the owner states it. If this shows up, the fix is to subtract a baseline
   captured at `beginInteractiveShape` rather than to widen or narrow anything else.
 * If the snap *still* does not engage, the next capture now answers it without another round of
   reasoning. Each `began` line carries `touchView` (`UITouch.view`'s class, or `nil` — distinct from
   `hitClass`, which re-runs `hitTest` as a fallback) and `gr`/`grNames` (the recognizers UIKit bound
   the touch to, read before dispatch). `gr:0` on the finger beside `gr:8` on the pencil means the
   touch never entered the gesture pipeline and the flag was not the answer; a full `grNames` with no
   `shape.touches` line means they were offered it and declined, and the `shouldIgnore ...` notes both
   recognizers now write say which and why.

If it turns out UIKit will not deliver that touch to this chain under any setting, the remaining
legitimate observation point is a `UIGestureRecognizer` on the `UIWindow` itself — the window is where
`WindowEventTap` already sees every one of these touches perfectly. That is a fallback, not a plan:
if the touch is being dropped *per view* rather than *per chain position*, a window-level recognizer
would be just as blind, and `gr:0` is what tells the two apart.

**No test is written, and a vacuous one would be worse than none.** The gesture is a pencil holding a
stroke while a finger joins it in a later event, and XCUITest can synthesise neither half: not the
pencil at all, and not the hold (see below — `thenHoldForDuration` delivers zero touch events). A
logic test over `ShapeGeometry.constrained` would pass without touching one line of the broken path.
What would test it is XCTest's private event synthesis (`XCPointerEventPath` /
`XCSynthesizedEventRecord`), the same capability `CanvasTransformFreezeUITests` needs for a real
two-finger drag.

One nearby behaviour is deliberately unchanged: a finger landing **before** the hold completes still
fails the stroke, because `shouldIgnoreAdditionalTouches` only answers true once a shape is following.
"Finger down during the hold" and "finger down after the shape appears" are different gestures and
only the second can ever snap.

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

## The onion skin renders unmasked (2026-08-15)

`PreviousCelOnionSkinSource` rasterizes the previous cel with `PixelOps.rasterize(cel:)` and applies
no mask, and `onionSkinView` sits below `sandwichBelowView` and is never blanked
(`CanvasView.swift:46` vs `:54`, shown at `:1416-1419`). So a masked layer's onion skin draws ink
outside the layer's own mask, at `onionSkinOpacity`.

**Half of this shipped as a fix and half is deliberately deferred.** The half that shipped: the
source asked for the cel at `currentFrame - 1`, but `addVectorLayer` mints ONE cel spanning the whole
scene, so from any frame but the first that lookup returned *the cel being drawn on* and the onion
skin ghosted the live artwork onto itself. Invisible normally — the layer's own pixels cover it — but
a mask uncovers it, which is how the product owner found it: a red layer masked by a black one showed
translucent red outside the mask on every frame of a block except frame 0. Fixed by stepping back
from the current *cel's* `startFrame`, which is what the doc comment always promised.

The residue: with two genuine cels, the previous cel's ghost is still unmasked, so the same leak
returns. Not fixed here because the owner is overhauling onion skin into a proper customizable menu
and this would be rewritten. When it is rewritten, reuse `resolveLiveMask(forLayerAt:)` /
`RenderNode.masksClipping(leafAt:in:)` rather than writing a second mask-resolution path, and mind
§6.4's warning that a `CALayer.mask` slot collision fails silently in whichever direction install
order decides.

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

`testFillToolBridgesOpenContourGapWhenGapClosingEnabled` is `XCTSkip`'d, and it is the single skip in
every clean full run. Three separate causes were found and fixed along the way (an originally
unbridgeable gap, `app.sliders.firstMatch` grabbing the wrong slider, and a synthetic drag too near
the screen edge dropping the next stroke) and the final containment assertion still fails. Next
steps: re-point the "outside" probe using `visibleCanvasBounds`/`safeOutsideCornerPoint`; if it still
fails, call `FloodFillEngine.fill` directly on synthetic wall data to tell a real leak from a
test-probe bug — the morphology math itself is verified correct in isolation. Re-enable by deleting
the `throw XCTSkip(...)` at the top of the test body.

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
