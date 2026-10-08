# Every presentation over the canvas, and why none of them is UIKit's

*Written 2026-08-18 from a sweep of every dismissible presentation in the app, after the owner reported
the menu-interrupted stroke a third time and asked whether it "extends far past the scope of 2 UI
menus". It did: seven of nineteen. Rewritten 2026-10-08 when the last system menu went (TODO "Every menu
over the canvas is an `AnchoredMenu`"); the sweep's tables and counts are in `git log`, and what is kept
here is the rule, the measurements that make it a rule, and the way it is enforced.*

## The rule

**Nothing the editor raises over the canvas is a UIKit presentation.** A colour picker, a list, a
pull-down, a press-and-hold menu and the timeline's menus are all `CanvasPresentation` cases, drawn by
the app inside its own view hierarchy as an `AnchoredMenu`, and closed by one `AnchoredMenuRouter` — a
single window-level observer that fails every touch immediately, so a touch that closes a menu **goes on
to do what it was aimed at**: the stroke lands, the pan pans, the toolbar button acts.

| to raise | write | drawn by |
|---|---|---|
| a picker, a list, a panel | `View.canvasPresentation(_:isPresented:canvasManager:)` | `canvasPresentationHost` |
| a pull-down (tap) | `CanvasMenu(_:canvasManager:identifier:) { rows } label: { … }` | `canvasPresentationHost` |
| a press-and-hold menu | `.canvasContextMenu(_:canvasManager:) { rows }` | `canvasPresentationHost` |
| the timeline's own five | `canvasPresentationRegistration` | `AnimationTimeline`'s menu layer |

Rows are `MenuItem`, `MenuSection`, `MenuDivider` and `MenuChoices` inside a `MenuList` (it scrolls past
three fifths of the room). A tap on a row acts and then closes the menu. A menu raised from inside another
presentation — the onion tint picker in the onion menu, a swatch's Delete menu in a colour picker, a
chip's menu in the interpolate panel — is drawn too (each presentation drawn is itself a layer), and
learns what it sits in from the view hierarchy (`EnvironmentValues.enclosingPresentation`), so a touch on
it never closes its parent.

**The one exception is the gallery**, a different screen (`ContentView` switches between the two): its
`Menu`s and `.contextMenu`s have no canvas to cancel a stroke on, and keep the system's. `ShareLink`
(the Actions panel's recordings, the export sheet) is the system share sheet, not a menu, and remains.

## Why — three measurements

**A `.popover` does not swallow the touch that dismisses it** (MEASURED 2026-08-18/20). The stroke
begins, the popover tears down, and the teardown arrives mid-sequence: seven popovers lost strokes, and
two of them closed an undo bracket on the way out, so they could lose history too. They were closed
centrally from `CanvasManager.interactionBegan` until the next finding made that the wrong place.

**A `.popover` swallows a drag outside it whole** (MEASURED 2026-09-06, TODO (39)). It presents behind a
screen-covering `_UIPassthroughGateGestureRecognizer`: the surface underneath does not scroll and the
popover does not dismiss either — menu up, a drag moved a cel block 0.0 pt; menu gone, 369 pt. Only a
tap got out. That is why the timeline's four menus were the first to be `AnchoredMenu`s.

**A two-finger touch under any UIKit presentation strands the canvas** (MEASURED 2026-09-24 on
`cbd248f`, TODO (110)). A `.popover`, a `Menu` and a `.contextMenu` all do the same: the drag pans, UIKit
tears the presentation down under it, and the recognizers the teardown was bound to — `canvas.pan`,
`canvas.pinch`, `canvas.rotation`, the taps, the catch-all — are stranded for good. That is the owner's
canvas freeze. `CanvasView.Coordinator.replaceStrandedRecognizers` replaces whatever is stranded 0.1 s
after the last finger lifts, so a freeze the editor did not cause (a share sheet, a stock colour picker)
still costs the artist nothing.

**A touch outside an open `Menu` begins a stroke the menu's teardown then cancels** (MEASURED
2026-10-07, iPad Pro 13" M4, iOS 26.5). The 2026-08-20 reading, that a `Menu` "absorbs the whole touch
sequence", was true only for a touch on the menu's own surface: it started ten points inside the menu's
frame, because the left rail was 20 pt wider. Started outside, the menu comes down, the stroke is drawn
and cancelled, the layer holds none of it, and the flight recorder announces *"Caught a canvas freeze
and fixed it"*. A `Menu` exposes no `isPresented` for `CanvasPresentation` to observe, so the family
could not be covered the way the popovers were; it had to stop being a `Menu`. The cases for every
family are in `CanvasPresentation`, and `MenuInterruptionUITests` draws straight through the blend-mode
menu, the one the owner met it in.

## How it is kept

- `CanvasPresentationLogicTests.testNoPopoverIsDeclaredAnywhereInTheApp` and
  `testNoSystemMenuIsDeclaredOverTheCanvas` read the app's source and fail naming the file and line on a
  `.popover`, a `Menu`, a `.contextMenu`, a `.confirmationDialog` or a `.pickerStyle(.menu)` anywhere
  but the gallery. `tools/presentation-census.sh` is the same check from a shell, and also lists the
  registered presentations and what remains UIKit's.
- `AnchoredMenuLogicTests` pins the placement arithmetic and the dismissal rule (nesting included);
  neither needs a simulator.
- `MenuInterruptionUITests` (a stroke through an open menu, and the timeline's four) and
  `CanvasMenuFamiliesUITests` (every family opened cold, a row picked, and a touch outside it closing it
  and still acting) pin what an artist sees.
- `CanvasTransformFreezeUITests` and `CanvasTransformLeavesStandingUITests` pin the two-finger case.

## What an `AnchoredMenu` is not

It is not a modal. It captures exactly what it covers and nothing else: no dismiss region, no gate, no
presentation. A `.alert`, a `.sheet` and a `PhotosPicker` are modal — nothing can be drawn under them, so
they cannot interrupt a stroke — and the router ignores touches that land on them
(`AnchoredMenuRouter`: a touch outside the root view controller's view is not "outside the menu").
