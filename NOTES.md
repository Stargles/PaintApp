# nov24-touch — canvas touch owner (working notes; deleted before merge)

## Map: what hears a canvas touch today
Bound to a canvas touch on the iPad (flights, `grNames`): `stroke.<layer>` (on StrokeCanvasView), `canvas.pan/pinch/
rotation/twoFingerTap/threeFingerTap/touchCounter` + the five presses + moveBoxCommit (on the container),
2× system gate, `window.touchCounter`, `PassiveTouchDownObserver`, 2× `_UIFlexInteraction.Pan`, (pencil) Scribble's
`PKTextInputDrawingGestureRecognizer`. Overlays: SelectionOverlay pan(1)+tap(1), FloatingPiece pans(1)+tap(1) =
recognizers; ObjectTransform, TextTransform, Shape, Guide, TextOverlay band = raw touches; UITextView = UIKit's own.
A finger landing while a drag takes a modifier hit-tests to HoldShieldView, outside the container.

## Cause (established from the flights)
stroke ↔ pan/pinch/rotation/(twoFingerTap→threeFingerTap) are one UIKit failure component
(`shouldRequireFailureOf`, `require(toFail:)`). UIKit resets a component only together; a UIPan that keeps a count of
touches it was never told ended (`failed touches:2`, third finger in an event of its own), or `ended touches:0` after a
cancelled+reissued contact, or a component whose only contact was cancelled before any recognized (`failed touches:0`),
is never reset, and everything tied to it stays terminal. The recognizers that never leave `.possible`
(`canvas.touchCounter`) were right in all 43.

## Design
* `CanvasTouchCore` (Models, pure): fed the complete live contact set each event; contacts, drawer, navigation, taps.
* `CanvasTouchRecognizer` (container, never leaves `.possible`, neither prevents nor is prevented, in no failure
  relation): rebuilds the contact set from `event.allTouches` filtered to the canvas plane, idempotent per event.
* `StrokeGestureRecognizer` never leaves `.possible` either; it draws only with the touch the core granted.
* No UIPan/UIPinch/UIRotation/UITap for navigation/undo/redo; no shouldRequireFailureOf.

## Arbitration table
| On the canvas plane | Winner | What it cancels |
|---|---|---|
| lone finger lands | drawer = that finger (stroke rec. draws unless pencil-only) + tap candidate | — |
| 2 fingers in one event | navigation/2-tap candidate, no drawer | — |
| 2nd finger joins a finger's stroke (anywhere on the plane) | navigation candidate | stroke handedOver (ink rolled back) |
| pencil lands, no nav live | drawer = pencil | finger's stroke handedOver; every finger down is spent (palm) |
| pencil lands while 2+ fingers navigate | navigation | pencil not granted |
| finger lands while a pencil is down | nobody (palm): spent for its life | never the pencil's stroke |
| pair moves past the slop | navigation (centroid+scale+turn), zoom and turn each past a slop of their own | in-flight fill drag; text follow |
| pair moves past slop while an assisted drag / another recognizer holds either touch | that drag; pair is spent | — |
| 3rd finger before the pair moved | 3-tap candidate; navigates only past a larger slop | — |
| 3rd finger while navigating | ignored; substitutes if one of the pair leaves | — |
| one of the pair lifts/cancelled while navigating | navigation holds the view | — |
| contact (re)joins while navigating | navigation re-baselines on the new pair; pan, zoom, turn continue, no jump | — |
| last finger lifts | navigation commits (viewTransform) | — |
| all lift, max 2 / 3 fingers, no nav, none cancelled/spent, quick | undo / redo | — |
| lone contact cancelled | nothing (finger stroke: interrupted, ink commits) | — |
| tracked contact vanishes without an end | treated as cancelled at the next event | stroke interrupted |
| app presses (fill/eyedropper/text/place/catchAll/moveBoxCommit) | unchanged: simultaneous with everything | fill drag cancelled on nav |
| trackpad pinch/rotate | was inert: `.changed` guard needs numberOfTouches>=2, indirect gestures report 0 | — |
