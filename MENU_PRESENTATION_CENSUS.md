<!-- Written 2026-08-18 from an exhaustive read-only sweep of every dismissible presentation in the app,
after the owner reported the menu-interrupted stroke a third time and said: "I'm not sure if this bug
extends far past the scope of 2 UI menus, frankly it is possible that many other ones have this problem."
They were right — for seven of the nineteen. This is the census that answers that question. The fix
merged 2026-08-20, and the twelve unverifiable ones were measured then too. -->

# Every dismissible presentation, and whether a stroke under it breaks

## The contract, and why it did not hold

*Past tense as of 2026-08-20: `CanvasPresentation` + `View.canvasPresentation` +
`CanvasManager.dismissPresentationsOverLiveCanvas()` are the registry, the declaration site and the
rule this section says did not exist. Kept because the shape of the absence is what made the defect,
and the next hand-written `interactionBegan` sink will look reasonable for the same reasons this one
did.*

`CanvasManager.interactionBegan` (`CanvasManager.swift:529`) is a bare `PassthroughSubject<Void, Never>`.
It is **sent** from four canvas-touch sites, all in `CanvasView.swift` — `:589` (stroke), `:2582`
(catch-all tap), `:2635` (fill press), `:2743` (eyedropper press).

It has **exactly two subscribers**, and each clears exactly one hand-named variable:

- `DrawingView.swift:139` — `if activePanel != .none { activePanel = .none }`
- `AnimationTimeline.swift:163` — `timelineMenu = nil`

There is **no registry of open presentations, no protocol, no shared dismiss-all entry point**, and
nothing that fails to compile or fails a test when a new `.popover` is added. A presentation is broken by
default and becomes safe only if someone remembered a line. The proof sits in the same file as the fix:
the author of the timeline sink wrote it for `timelineMenu` and did not clear the two sibling popovers
declared nine lines above it.

**One correction to the repo's own record.** `StrokeGestureRecognizer.swift:274` says the
`AnimationTimeline` sink "closes the three popovers". It does not. "Three" there means the three *cases*
of `TimelineMenu` (block / gap / loop) behind a **single** popover. The two other `@State` popovers in
that same file are untouched.

**There are no tap-to-dismiss catcher layers anywhere.** The only full-size `Color.clear`
(`AnimationTimeline.swift:218`) is a popover *anchor* carrying `.allowsHitTesting(false)` (`:193`).
Every dismissal in this app is system presentation dismissal.

## Counts

**BROKEN 7 · UNKNOWN 12 · SAFE 44** — the sweep of 2026-08-18, before anything was fixed.

**Settled 2026-08-20: BROKEN 7 · SAFE 56.** The twelve UNKNOWNs are **safe, MEASURED** — see "The
question the source could not answer", below, which is now answered. So the true size of the defect
was seven, not nineteen. All seven are fixed: each is declared through `View.canvasPresentation`
with a case in `CanvasPresentation`, closed centrally by
`CanvasManager.dismissPresentationsOverLiveCanvas()`, and a stroke a teardown does interrupt now
commits rather than vanishing (`StrokeGiveUp.interrupted`).

## The four distinct versions of the problem

**Version 1 — two more `.popover`s in `AnimationTimeline.swift` itself.** Onion skin (`:424`) and
interpolate (`:470`), sitting 260 and 300 lines below the sink written to fix exactly this class of bug,
which hard-codes `timelineMenu = nil`.

**Version 2 — five `.popover`s hung off the layer rail and its options panels.** *(Three of the five,
since 2026-08-27: the two `EffectSection` rows moved to the bottom bar with the knobs they belong to —
see "Where two panels present *from* changed", below. They are still registered and still closed
centrally; only the anchor moved.)* View selector
(`LayerPanel.swift:90`), canvas background colour (`:188`), value-layer colour (`:494`), effect outline
colour (`EffectSection.swift:438`), gradient-stop colour (`EffectSection.swift:833`). These *look*
protected because `activePanel = .none` deletes their host view — but that is a teardown caused **by** the
same touch one layer up, not a dismissal that completes **before** it, so the presentation still comes
down mid-sequence. **Two of them close an undo bracket on the way out** (`EffectSection.swift:448`,
`LayerPanel.swift:505`), so this version can lose history, not just ink.

**Version 3 — nine `Menu` / `.contextMenu` pull-downs over the canvas, with no external state at all**
for anyone to clear: blend mode ×3 (`LayerPanel.swift:415`, `:590`, `:969`), add-layer (`:94`), palette
management (`ColorPickerPanel.swift:356`), swatch delete (`:419`), effect picker
(`EffectSection.swift:369`), motion-group chip (`MotionGroupRow.swift:126`), guide fetch
(`GuideRow.swift:155`). **Whether these take the same recognizer-stranding path is the one thing the
source cannot settle** — see Open question below.

**Version 4 — nested presentations inside an already-unprotected one.** The stock `ColorPicker` inside the
onion-skin popover (`OnionSkinPanel.swift:326`), and `ShareLink`'s activity popover inside the Actions
panel (`ActionRecorderControls.swift:142`).

## BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first

*All seven are fixed as of 2026-08-20. Each now names its case in the "Holds it open" column's
`CanvasPresentation` twin and is declared through `View.canvasPresentation`; the table is kept as the
record of what was wrong, not as a list of open defects.*

| file:line | What it is | Holds it open |
|---|---|---|
| `AnimationTimeline.swift:424` | Onion Skin options panel (380×640) | `showOnionSkinOptions` |
| `AnimationTimeline.swift:470` | Interpolate options | `showInterpolateOptions` |
| `LayerPanel.swift:90` | View Selector dropdown (260×300) | `showViewSelector` |
| `LayerPanel.swift:188` | Canvas background colour picker (300×420) | `showBackgroundColorPicker` |
| `LayerPanel.swift:494` | Value-layer colour picker (300×420) | `showingValueColorPicker` — **closes an undo bracket at `:505`** |
| `EffectSection.swift:438` | Outline colour swatch picker | `showingColorPicker` — **`onEditBegan`/`Ended` bracket at `:448`** |
| `EffectSection.swift:833` | Per-gradient-stop colour picker | `colorPickerIndex` |

## SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified

**Measured 2026-08-20 and safe — see "The question the source could not answer", below, for how.**
Listed as they were found:

`Menu` / `.contextMenu` / stock `ColorPicker` / `ShareLink`, twelve of them: `MotionGroupRow.swift:126`
and its nested `Picker` at `:134`, `GuideRow.swift:155`, `LayerPanel.swift:94`, `:415`, `:590`, `:969`,
`ColorPickerPanel.swift:356`, `:419`, `EffectSection.swift:369`, `ActionRecorderControls.swift:142`,
`OnionSkinPanel.swift:326`.

## Why `.popover` is the hazard and `Menu` is not

The repo's own diagnosis (`AnimationTimeline.swift:146-162`, `StrokeGestureRecognizer.swift:270-278`)
records as observed fact that a `.popover`'s outside-touch **does not swallow the touch**: the stroke
begins, and the teardown lands mid-sequence. `Menu` and `.contextMenu` present through a different UIKit
path, and on 2026-08-18 nothing in this repo had verified it. It has been now, and it swallows — the
measurement is below. `.alert` / `.sheet` / `PhotosPicker` are modal — no stroke can start under them,
which is why all of those are SAFE.

## SAFE, and worth knowing why

Everything reached through `activePanel` is safe *at the top level* — the tool dropdowns, the layer rail,
the select dock, the layer/folder options panel (transitively, via `onChange(of: activePanel)` at
`DrawingView.swift:143`). The Move bar, the notice pill, the perf HUD and the REC badge have no
outside-tap dismissal at all. The in-place row swaps in `LayerPanel` (mask and effect sub-menus, layer and
folder) replace content rather than presenting. Everything in `GalleryView` is safe because no canvas
exists on that screen (`ContentView.swift:19-25` switches screens). Four of the five panels this
paragraph used to name — `SelectPanel`, `StrokeSettingsPanel`, `MaskTuningSection` and
`InterpolatePanel` — contain no presentations at all.

**The fifth, `TextSettingsPanel`, grew three, and the sentence that said otherwise was false from Add
Text's later stages until 2026-08-27.** Found by `tools/presentation-census.sh`, logged in
[BUGS.md](BUGS.md), and corrected here: the font-family `Menu`, the face `Menu` and a stock
`ColorPicker`. All three are in the count of fourteen the script prints — they were never missing from
the tooling, only from this file's prose.

## Where two panels present *from* changed, 2026-08-27, and what that did and did not move

The effect knobs and the Add Text settings are now bottom bars (`EffectSettingsBar`,
`DrawingView.bottomDock`) rather than a sub-panel in the layer rail and a dropdown under the top
toolbar. Six of this document's sites therefore present from a new anchor. **None of them changed
class**, and the reasoning is the mechanism rather than the geometry:

- **The two registered `.popover`s in the effect bar** — the outline colour swatch and the per-stop
  gradient colour, Version 2's last two rows — are still declared through `View.canvasPresentation`
  with their same `CanvasPresentation` cases, so `dismissPresentationsOverLiveCanvas()` still closes
  them on a canvas touch. What changed is only that Version 2's heading, "hung off the layer rail and
  its options panels", is now true of three of its five rather than all five.
- **Version 3's "effect picker" moved with them**, and is worth naming precisely because the label is
  misleading: it is `pickerRow`'s `Menu` — the Posterize effect's Screen dropdown, *inside* the
  settings panel — not the catalogue menu that chooses an effect, which is `valueBlendModeRow`'s and
  `nodeOperationRow`'s and stayed in the rail. It is a `Menu`, so the paragraph below applies to it.
- **The three unregisterable presentations in `TextSettingsPanel`** now open upward from near the
  bottom of the screen instead of downward from the top-leading dropdown. Both anchors put them over
  live canvas, so this is not a presentation that is *newly* able to overlap the artwork — it is the
  same overlap in a different place. The two `Menu`s are SAFE for the reason every other `Menu` in
  this app is (below), and that reason is about `UIMenu`'s dismiss region, which does not depend on
  where the menu is anchored. **Spot-checked on iPad Pro 13" (M4) / iOS 26.5, 2026-08-27**: with the
  font `Menu` open from the bottom bar and the text tool armed, one tap on the canvas dismissed the
  menu and placed **no** text box — the dismiss region absorbed it, exactly as
  `MenuInterruptionUITests` measured for the blend-mode menu.
- **The stock `ColorPicker` is still the open question**, unchanged and unanswered. One tap outside it
  also dismissed it without placing a box in the same session, which is *not* the measurement
  [BUGS.md](BUGS.md) asks for: `.popover`'s failure mode is a **drag**, where the outside touch begins
  a stroke and the teardown lands mid-sequence, and a tap cannot distinguish that. Treat this row as
  UNKNOWN until somebody runs `MenuInterruptionUITests`' shape against it.

## The question the source could not answer — MEASURED 2026-08-20, and the answer is no

**Does a SwiftUI `Menu`/`.contextMenu` outside-touch pass through to the canvas the way `.popover`
demonstrably does here?** That single fact separated the twelve UNKNOWNs from BROKEN.

**It does not.** `MenuInterruptionUITests.testDrawingStraightThroughAnOpenBlendModeMenu` opens the
layer's blend-mode `Menu` and draws straight through it, in the shape of `CanvasTransformFreezeUITests`.
On iPad Pro 13" (M4), iOS 26.5, three readings, all of one piece:

| reading | result |
|---|---|
| Does the menu come down? | **No.** `layerOptions.blendMode.multiply` is still on screen after the drag. |
| Did the stroke reach the canvas? | **No.** The layer's committed `.paint` count is 0. |
| Does the canvas still work? | **Yes.** The next stroke commits (count 1) and the pinch still moves the canvas. |

A `Menu`'s dismiss region absorbs the whole touch sequence rather than passing it through — it does
not even take a *drag* as a dismissal, where a `.popover` is dismissed by the very touch that starts
the stroke. So the stroke that would have been interrupted never begins, and there is no sequence for
a teardown to land in the middle of. **The true size of the defect was seven, not nineteen.**

`testTheSameStrokeWithNoMenuOpenCommitsNormally` is the control and it is not decoration: the first
draft of that class counted *raster* strokes on a layer that is vector by default, so it read 0
through the menu and would have reached the right answer for a reason that could not have been wrong.
The control failed, and that is what caught it. Read the `.vector` marker here, never
`readLayerStrokeCount`.

**What this does not say.** It measures SwiftUI's `Menu` on this OS. `.contextMenu` presents through
the same `UIContextMenuInteraction` family and is taken with it; the stock `ColorPicker`'s own
presentation and `ShareLink`'s activity popover are not separately measured, and both sit *inside*
presentations already covered (`OnionSkinPanel` and the Actions panel), so a stroke reaches them only
through a parent that is already registered.

## Coverage limits of this sweep

`CanvasView.swift` (2842 lines) was read around its four `interactionBegan.send()` sites and its overlay
wiring, not end to end; its CALayer canvas decorations (`ShapeOverlayView`, `GuideOverlayView`,
`SelectionOverlayView`, `FloatingPieceOverlayView`, `ObjectTransformOverlayView`) were confirmed by grep
to have no dismiss-on-outside-touch behaviour but not read fully. The `PaintSoftwareUITests` target was
excluded.
