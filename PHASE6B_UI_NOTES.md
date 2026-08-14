# Phase 6b — §6.5 mask UI / §6.6 lifecycle — worker notes

Scope: §6.5's panel and mask-edit mode, §6.6's lifecycle. Did not touch §6.4 (live stroke feedback)
or `CanvasView.swift`'s `strokeView` code path — that's the other worker's.

## What shipped, and where

**Model / session logic — all in `PaintSoftware/Models/CanvasManager.swift`** (no new file):
`maskEditTarget: MaskSource?` (the modal state, §6.5 wants it here so the canvas can read it too),
`beginMaskEdit(for:)`, `endMaskEdit()`, `toggleMaskSource(_:)`, `isMaskSource(_:)`,
`maskEditAllows(_:)`, `maskEditCanvasDim(forLayerAt:)`, `alphaMask(for:)`, `setMaskEnabled(_:for:)`,
`setMaskInvert(_:for:)`, `removeMask(for:)`. Deliberately **not** a new `CanvasManager+MaskEdit.swift`
extension file: `PaintSoftwareUITests` hand-lists a group of app sources it compiles a second time
(`CanvasManagerTestSupport.swift`'s header explains why — `@testable import` type-checks but doesn't
link for a UI-testing bundle), and a new file needs a `project.pbxproj` entry in that group to be
visible to the logic tests. Everything above lives in a file already in that group, so no pbxproj
edit was needed.

**Panel — `PaintSoftware/Views/LayerPanel.swift`**: a `maskSection` free function (mirrors
`blendModeRow`/`optionsAction`'s sharing pattern) used by both `LayerOptionsPanel` (beside Fill
Reference, as specced) and `FolderOptionsPanel` (beside Pass Through) — §6.2 puts `alphaMask` on
both `Layer` and `LayerFolder`, so both options menus get the toggle. The toggle binds straight to
`isEnabled`; turning it on always calls `beginMaskEdit` (even for a mask that already has sources —
literal reading of "turning it on enters mask-edit mode"). Once a mask exists, an "Invert Mask"
toggle and an "Edit/Choose Sources" row appear. `LayerPanel`'s header is replaced by a `maskEditBar`
("Mask Sources — `<name>`" + **Done**) while a session is open — the explicit exit §6.5 asks for,
since the small options popover that opened the session is long closed by then.

**Picker — `LayerStackListView.swift` + `LayerStackCell.swift`**: `LayerRowModel` carries
`isMaskEditActive`/`isMaskSourceSelected`/`isMaskEligible`/`isMaskEditTarget`, computed once per row
from `CanvasManager.isMaskSource`/`maskEditAllows`. `didSelectRowAt` routes a tap to
`toggleMaskSource` while a session is open, filtered through `maskEditAllows` (same `canMask` call
the row used to decide whether to offer itself — no second rule). `LayerStackCell` swaps the
opacity slider / current-marker / folder-options button for a single trailing glyph (checkmark =
selected, circle = eligible, pencil = the node under edit) and dims ineligible rows to 0.3 alpha,
the edited node's own row to 0.55. Swipe-delete/duplicate, long-press reorder, and pinch-merge are
all disabled mid-session — a structural edit then would nest into the open `beginStructureGesture`
bracket rather than being refused, which is a stranger outcome than just not starting it.

**Canvas dim — `CanvasView.swift`, one line**: `reconcileLayers`'s existing `targetAlpha` computation
(already folding `effectiveOpacity`/group opacity into the one number Core Animation takes) now also
multiplies by `canvasManager.maskEditCanvasDim(forLayerAt:)`. This is the *only* line touched in that
file, and it is `host.alpha`, not anything under `host.strokeView` — flagging it explicitly per the
brief's boundary, since it's in the same file the other worker owns a path in, even though it's a
different, non-overlapping line.

## §6.6 lifecycle — what already existed vs. what was added

**Deletion dropping a source was already wired in 6a.** `deleteLayer`/`deleteFolder` both already
call `dropMaskSource` inside their own `withStructureUndo` (`CanvasManager.swift:547,944`), and 6a's
`MaskParityLogicTests.testDeletingASourceDropsItAndDisablesTheMask`/
`testUndoRestoresTheSourceAndTheMaskTogether`/`testDeletingAFolderDropsItAsAMaskSource` already cover
it. Nothing to build here — checked it before assuming it needed wiring, per the brief.

**Hidden source still masks was also already true**, since `toggleLayerVisibility` never touched
`alphaMask` to begin with (only `isFillReference`). Added
`testTogglingVisibilityDoesNotClearTheMaskUnlikeFillReference` as the regression guard for that
staying true, since it's a "doesn't do a thing" property that a future edit could grow silently —
6a's own `testAHiddenSourceStillContributesItsAlpha` proves the *render* result but goes through the
fixture's raw `isVisible = ...`, not the panel's actual `toggleLayerVisibility` call.

**Session coalescing was net-new**: `beginMaskEdit`/`endMaskEdit` bracket with
`beginStructureGesture`/`commitStructureGesture`, and every `setAlphaMask` in between nests via
`withStructureUndo`'s depth guard (same mechanism the opacity slider already uses) — no new undo
machinery, just using what was there. `testMaskEditSessionCoalescesEveryPickIntoOneUndoStep` pins it:
four picks and an invert land as one step.

## Where §6.5/§6.6 as written needed a judgment call

- The doc names one toggle "beside Fill Reference" in `LayerOptionsPanel`; it doesn't say a folder
  needs the same control. Added it to `FolderOptionsPanel` too — §6.2 is explicit that a group can be
  masked, and the model already carries `alphaMask` on `LayerFolder`, so leaving folders unable to
  ever get a mask through the UI would have been a gap, not a scope cut.
- "Expose `isEnabled` and `invert`" reads as two switches. I bound the *toggle itself* to `isEnabled`
  (turning it on/off is exactly what enters/exits the session's created-mask state) and added
  `invert` as a second control that only appears once a mask exists — there's no meaningful "invert" on
  no mask. This wasn't spelled out either way in the brief.
- `toggleMaskSource` force-sets `isEnabled = true` when a row is picked, even if the mask had been
  paused via the panel's off position. So re-opening the picker on a *disabled* mask via "Edit
  Sources" and touching any row silently re-enables it. Simpler than threading a "stay paused while
  editing" mode through, and not a case the brief called out — flagging it as the one place session
  semantics could plausibly want a different answer.
- Canvas dimming is two-state (source-eligible vs. not), not the row picker's three. There's no
  separate on-canvas host per folder to mark distinctly (Core Animation gets one flat sibling per
  *layer*, per §1), and the edited node's own layer reads the same as "ineligible" there — same
  underlying `canMask` self-mask case, just without the picker row's separate pencil glyph to say why.

## Testing

Fast tier only, per instructions — did not run the 22-minute XCUITest suite.

```
xcrun simctl shutdown E7576E92-8EB7-489B-962B-6A2E61852EC0   # already shut down
xcrun simctl erase E7576E92-8EB7-489B-962B-6A2E61852EC0
xcrun simctl boot E7576E92-8EB7-489B-962B-6A2E61852EC0
```

`totalTestCount: 757`, `passedTests: 757`, `failedTests: 0`, `result: "Passed"` (read from
`xcresulttool get test-results summary`, not the `** TEST SUCCEEDED **` banner). New cases, all
passed: `MaskParityLogicTests.testMaskEditSessionCoalescesEveryPickIntoOneUndoStep`,
`testMaskEditRefusesASelfMaskAndAMutualCycleEvenIfTapped`,
`testTogglingVisibilityDoesNotClearTheMaskUnlikeFillReference`. Added to the existing
`MaskParityLogicTests.swift` rather than a new file, so no `project.pbxproj` edit was needed for the
tests either.

`xcodebuild build -destination 'generic/platform=iOS Simulator'` also confirmed clean before running
tests.
