# Handoff — 2026-08-27 (session 69)

<!-- This file is both the state of the repo and the prompt that starts the next session. It used to
be two files, HANDOFF.md and nextprompt.md, and they drifted apart within a single day because the
same state had to be written twice. One file, one copy of the truth. -->

## Start here — paste this to begin the next session

```
Read HANDOFF.md, then CLAUDE.md and TODO.md.

You are the orchestrator: delegate the building and the test runs, do the merging and the reading
inline.

`main` is at **1725 fast-tier tests (1722 passed, 0 failed, 3 skipped)**, nothing in flight, no
worktrees, no `tmp/*` branches, no simulator clones, pushed to `origin/main`.

**Start by asking me what I found on the device on the three reports still open** — each has a
four-second experiment designed and waiting, not another read of the code:

1. **(3) distort half — text invisible in distort mode.** Distort a box, then **tap into it**.
   `isFlatEditing` swaps the layer to `setAffineTransform` while the caret is live. Words reappear
   flat, vanish on tapping away → the fault is the perspective assignment (a CALayer/render-server
   issue, not the in-process software path the first-pass diagnosis blamed — that path was refuted
   because the symptom is about the render server, not `CALayer.render(in:)`). Invisible in BOTH
   states → the glyph bitmap, sharing a cause with the small-box bug fixed this pass. Also look at
   the nine grips: in perspective + no glyphs = the CA hypothesis; a box that was blank *before* the
   drag = the raster hypothesis. The first distort drag flips `autoSize` true→false, which flips
   `clip:` in the RenderKey and forces a re-render — the one provable change to the glyph raster at
   the moment text disappears.
2. **(4) pencil tap does not raise the keyboard.** App-side path is verified clean — `beginTextSession`
   has one non-test caller, no branch a pencil takes that a finger cannot, so if the box appeared,
   `becomeFirstResponder()` was called. **Turn pencil-only OFF in Actions first** (else a finger tap is
   refused at `CanvasView.swift:2869` and the test proves nothing), then Add Text → tap empty canvas
   with a **finger**. Keyboard comes up → real pencil/finger split. Stays down → the responder is
   refused for everyone, pencil is innocent. `focusEditor()`'s return value does NOT discriminate
   (true under the Scribble story too) — `textIsFocused` / `textGestureActive`
   (`CanvasManager.swift:2227`/`:2234`, plain vars, no `ActionRecorder` hook yet) plus
   `keyboardWillShowNotification` do. Add those hooks before spending a device pass.
3. **(6) the UI freeze.** Strongest live candidate: `CanvasManager.selectBrush(_:)`
   (`CanvasManager.swift:557-568`) omits `.text` from its `selectedTool != .eraser && selectedTool !=
   .fill` exclusion list, so picking a brush preset flips the tool off `.text` without
   `commitAllInteractiveState()` — the same hand-maintained-list shape `Tool.paintsOnCanvas`'s doc
   comment exists to prevent. Reachability is **unproven**: `BrushSettingsPanel.swift:20` is the only
   caller and needs `activePanel == .brush`, which `TopToolbar.swift`'s committing route
   (`selectBrushToolAndTogglePanel`, :174-182) appears to block whenever `selectedTool == .text`. **The
   discriminating question, which no run can answer: when it locks, does the timeline still animate
   and do the marching ants still march?** Yes → a dead-input overlay. No → a real main-thread hang.
   One `ActionRecorder` capture names it outright.

**The Move-tool expansion is still the live thread**, unchanged since session 68 — nobody touched it
this pass, which was entirely the seven device reports:
  1. ~~the lassoed piece's rotate/scale nodes~~ — done
  2. ~~the Move menu~~ — done
  3. **Freeform + the yellow box-only knob + placed images holding a stretched shape** — designed,
     not started. Splits into three branches; 3a ships a working Freeform with **no renderer change**.
     The design is in the git history of session 68; find it before re-deriving it.
  4. ~~the shared `Homography` solver~~ — done, as ADD_TEXT Stage 5
  5. **Distort on both tiers**, consuming that solver, with my ink-deformation toggle defaulting off
     — report (3)'s distort half above is a bug in text's own Stage 5 distort, not this stage, but
     both roads lead through the same solver and the same suspects.

Two questions still owed, unchanged for days — ask when they block work:
  - Save semantics when a project loaded with something unreadable: may saving overwrite the good
    original, refuse, or prompt? (A branch shipped "prompt once, then remember"; confirm it.)
  - Which faces belong in the font picker's favourites strip.
```

---

## State

`main` = `ef64506`, pushed to `origin/main`. Clean tree, no worktrees, no `tmp/*` branches, no
simulator clones.

Final verification on the merged tree: **1725 total / 1722 passed / 0 failed / 3 skipped**,
`result: "Passed"`, exit 0. Base was 1709; delta +16 = 4 (two-images) + 12 (text floor). Static
`func test` count went 1826 → 1842, matching.

## What landed

Four things merged, closing four of the owner's seven device reports (a fifth, (5), was answered
last pass as not-a-defect). TODO.md's "Done this pass" has the full writeups; what follows is only
what a later reader would otherwise rediscover the hard way.

**Report (2), the lasso's live outline, had two independent causes, not one.**
`liveShadowLayer.isHidden = true` permanently hid the blue half of the live preview, leaving a 1.5pt
white dash invisible on white paper, and separately `liveLayer` never had the marching-ants animation
added at all. Wrapped the live path assignment in a `CATransaction` with actions disabled (precedent:
`ShapeOverlayView.swift:218-222`, `GuideOverlayView.swift:155-158`) so the preview stops trailing the
stylus. **No test** — `SelectionOverlayView` type-checks under `@testable import` but fails to *link*
in the UI-test target, and is not among the pure Foundation/CoreGraphics sources compiled a second
time into it. Pinned by the owner's eye only.

**Report (1), the Move preview vanishing, was `isSandwichEngaged` missing an escape hatch that was
added for raster and never extended to vector.** `389876b` (2026-08-12) wrote the raster
`floatingPiece` carve-out before the vector lasso move existed; `vectorFloat` was never added
alongside it. Any effect/mask/blend/group-buffer anywhere in the tree makes
`RenderTree.needsCompositorOnCanvas` true, which engages the sandwich, which blanks every layer host
at rest — including the one holding the float's pixels. The hole is punched correctly
(`suppressedElementIDs`); it is the float being dropped underneath it. **Two corrections to the
owner's report, both in the fix's favour**: it is not "sometimes" — it happens on *every* move with
any effect/mask/blend/group-buffer in the tree — and it is not specific to layers *over* the moved
one, since `needsCompositorOnCanvas` walks the whole tree. Cost recorded in the doc comment:
disengaging also does `setContentMask(nil)`, so alpha-mask clipping is lost while a piece floats. **No
test** — `isSandwichEngaged` is private on the coordinator, unreachable from the fast tier; a real pin
needs an XCUITest over a document with an effect layer and a live lasso move.

**A canvas-touch archaeology correction, not a report fix on its own — `handleTextPress` was the
app's one bare `interactionBegan.send()`.** The contract commit (`3a68adb`, one closed set of
presentations) was authored *before* Add Text stage 1 (`6d404d0`) by 23 minutes, but landed *after*
it on `main` because the contract branch was rebased on top — so its "converted all four canvas-touch
sites" comment was accurate on its own pre-rebase base and stale by the time it shipped. A distinct
hazard from the "two branches that cannot see each other" shape already in CLAUDE.md: this is *one*
branch whose own count expired underneath it during a rebase. Fixed, and the same stale-four miscount
in `CanvasPresentationLogicTests.swift:168` was fixed too. This is **not** the owner's freeze (6) —
with `.text` selected the stroke recognizer receives no touches, so there was nothing to strand.

**Report (7), two images on a vector layer, was a hard-coded import centre — image 2 landed on a
bit-identical `CGPoint` to image 1, and `splitForLassoMove` decides membership purely by stored
centre, so no lasso loop could ever contain one without the other.** Fixed with
`VectorCanvas.addImage(canvasSpaceElement:canvasPosition:canvasFit:)` (`VectorLayer.swift:670`,
beside `addStroke`/`addFill`), mapping through `_transform.inverted()` and cascading 24pt per existing
image in *local* units under one lock. **The first draft's arithmetic was wrong**: adding 24pt to a
canvas-space centre that is then stored as local coordinates leaves the larger misplacement in place.
Appending was considered and rejected — `addImage`'s kind-sorted insert is documented and pinned by
`testAddingElementsKeepsTheKindOrderExceptForAFillWhichGoesOnTop`, and appending would not have fixed
the collision anyway. 4 tests, verified non-vacuous: 3 of 4 fail against pre-fix code, the 4th
correctly still passes (pins an invariant the original already satisfied).

**Report (3)'s *small-box* half, text invisible in a box too small: `TextLayout.draw` fed
`CGPath(rect:)` of the raw box to CoreText, which drops any line that does not fit entirely — a box
shorter than one line yields zero lines, not a clip.** MEASURED: a 64pt line needs a 76.7pt path, and
the old flat `minimumExtent = 24` was a total blackout. Fixed by anchoring layout on the box's *top*
so overflow hangs below, and by giving the box per-axis floors: height >= one measured line (via
`measure`, never `font.lineHeight`, which is short by 3x at the top of the range), width >= the run
CoreText will not subdivide. **A brief premise was empirically wrong and was corrected**: the brief
said floor the width at "the widest unbreakable word", but MEASURED, CoreText's `.byWordWrapping`
*breaks inside* a word that will not fit — one character per line. The implemented floor asks the
framesetter what it actually refuses to subdivide (46.2pt "Hello world", 86.2pt at 40pt tracking,
55.4pt for a Japanese sentence with no spaces). A literal "never smaller than its text" floor from the
*wrapped* layout was rejected because it chases itself — narrowing increases required height — and
would make boxes un-narrowable. Distort is exempted on both paths; the floor latches on
`TextFrameDrag` at touch-down so a 60Hz drag runs no layout. 12 tests (5 + 7 across the two commits).

## Still open, blocked on the owner's iPad

Three of the seven reports could not be closed by reading. An adversarial verification tier refuted
the first-pass diagnosis for all three, which is why they are open rather than fixed — see the paste
block above for each one's experiment. **(3)'s distort half**, **(4)** the pencil-tap keyboard, and
**(6)** the UI freeze.

Also found and not done: three uncensused presentations in `TextSettingsPanel.swift` — see BUGS.md.

## Carried, deliberately not done

- **Move stage 3 (Freeform) and stage 5 (Distort)** — see the paste block. Stage 3's design named two
  traps worth keeping: `allowedHandles` defaults to *all cases*, so new handles switch themselves on
  everywhere including the whole-layer box; and `ImageRef` uses synthesized `Codable`, so adding
  non-optional fields breaks every existing document.
- **`TextFrame.homography` has no validity check on the decode path** — unchanged.
- **The `.projective` vector flatten re-rasterises per invalidation, not per commit** (BUGS.md) —
  unchanged, blocked on `TextRecipe` gaining `Hashable`.
- **The raster Move's undo half** of ruling 4, and **PERFORMANCE.md item 14's expensive half** —
  unchanged.

## Still true, carried forward

`LASSO_MOVE.md` §5 carries fifteen owner rulings; do not re-litigate any. ADD_TEXT.md Stage 5 is
shipped and Stage 6 is the deferred-polish list. `ARCHITECTURE_REVIEW.md`'s finding 1 is closed;
findings 2–4 (eleven hand-written cache keys, silent save-failure returns, a layer property living in
four hand-kept structs) are open and unruled.
