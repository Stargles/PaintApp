<!-- Written 2026-08-18 from an exhaustive read-only sweep of every dismissible presentation in the app,
after the owner reported the menu-interrupted stroke a third time and said: "I'm not sure if this bug
extends far past the scope of 2 UI menus, frankly it is possible that many other ones have this problem."
They were right. This is the census that answers that question. The fix is on tmp/menuinterrupt. -->

# Every dismissible presentation, and whether a stroke under it breaks

## The contract, and why it does not hold

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

**BROKEN 7 · UNKNOWN 12 · SAFE 44**

## The four distinct versions of the problem

**Version 1 — two more `.popover`s in `AnimationTimeline.swift` itself.** Onion skin (`:424`) and
interpolate (`:470`), sitting 260 and 300 lines below the sink written to fix exactly this class of bug,
which hard-codes `timelineMenu = nil`.

**Version 2 — five `.popover`s hung off the layer rail and its options panels.** View selector
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

| file:line | What it is | Holds it open |
|---|---|---|
| `AnimationTimeline.swift:424` | Onion Skin options panel (380×640) | `showOnionSkinOptions` |
| `AnimationTimeline.swift:470` | Interpolate options | `showInterpolateOptions` |
| `LayerPanel.swift:90` | View Selector dropdown (260×300) | `showViewSelector` |
| `LayerPanel.swift:188` | Canvas background colour picker (300×420) | `showBackgroundColorPicker` |
| `LayerPanel.swift:494` | Value-layer colour picker (300×420) | `showingValueColorPicker` — **closes an undo bracket at `:505`** |
| `EffectSection.swift:438` | Outline colour swatch picker | `showingColorPicker` — **`onEditBegan`/`Ended` bracket at `:448`** |
| `EffectSection.swift:833` | Per-gradient-stop colour picker | `colorPickerIndex` |

## UNKNOWN — presents through a path this repo has never verified

`Menu` / `.contextMenu` / stock `ColorPicker` / `ShareLink`, twelve of them: `MotionGroupRow.swift:126`
and its nested `Picker` at `:134`, `GuideRow.swift:155`, `LayerPanel.swift:94`, `:415`, `:590`, `:969`,
`ColorPickerPanel.swift:356`, `:419`, `EffectSection.swift:369`, `ActionRecorderControls.swift:142`,
`OnionSkinPanel.swift:326`.

## Why `.popover` is the confirmed hazard and `Menu` is not (yet)

The repo's own diagnosis (`AnimationTimeline.swift:146-162`, `StrokeGestureRecognizer.swift:270-278`)
records as observed fact that a `.popover`'s outside-touch **does not swallow the touch**: the stroke
begins, and the teardown lands mid-sequence. `Menu` and `.contextMenu` present through a different UIKit
path whose touch-passthrough behaviour **nothing in this repo verifies**. `.alert` / `.sheet` /
`PhotosPicker` are modal — no stroke can start under them, which is why all of those are SAFE.

## SAFE, and worth knowing why

Everything reached through `activePanel` is safe *at the top level* — the tool dropdowns, the layer rail,
the select dock, the layer/folder options panel (transitively, via `onChange(of: activePanel)` at
`DrawingView.swift:143`). The Move bar, the notice pill, the perf HUD and the REC badge have no
outside-tap dismissal at all. The in-place row swaps in `LayerPanel` (mask and effect sub-menus, layer and
folder) replace content rather than presenting. Everything in `GalleryView` is safe because no canvas
exists on that screen (`ContentView.swift:19-25` switches screens). The five panels `SelectPanel`,
`TextSettingsPanel`, `StrokeSettingsPanel`, `MaskTuningSection` and `InterpolatePanel` contain no
presentations at all.

## The one open question the source cannot answer

**Does a SwiftUI `Menu`/`.contextMenu` outside-touch pass through to the canvas the way `.popover`
demonstrably does here?** That single fact separates the twelve UNKNOWNs from BROKEN.
`CanvasTransformFreezeUITests` pins only the popover case, and no comment in the tree addresses it.
Settle it empirically — an ActionRecorder capture over a blend-mode menu, or an XCUITest in the shape of
`CanvasTransformFreezeUITests` — before assuming either answer.

## Coverage limits of this sweep

`CanvasView.swift` (2842 lines) was read around its four `interactionBegan.send()` sites and its overlay
wiring, not end to end; its CALayer canvas decorations (`ShapeOverlayView`, `GuideOverlayView`,
`SelectionOverlayView`, `FloatingPieceOverlayView`, `ObjectTransformOverlayView`) were confirmed by grep
to have no dismiss-on-outside-touch behaviour but not read fully. The `PaintSoftwareUITests` target was
excluded.
