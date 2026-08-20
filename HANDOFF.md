# Handoff — 2026-08-20

**`TODO.md`'s "In flight" is empty.** Every ask the owner had on that list is merged, plus Add Text
stage 1 and Tier A of the performance programme. Seven branches landed; `main` is at
**1357 fast-tier tests passing, 0 failing, 3 skipped**, verified twice on a fresh simulator after the
merges rather than only on each branch's own base.

Nothing is in flight. No worktrees, no `tmp/*` branches, no simulator debris.

## What shipped

| what | the fix, in one line |
|---|---|
| **Canvas border ignored padding** | "The canvas edge" is the *artwork rect*, inset from the buffer by `canvasPadding` — the shader now carries the inset, and the edge is an unconditional barrier between pixels rather than a gap-closing bridge conditional on nearby ink. |
| **Lasso filled the whole canvas** | Rebuilt as morphological hole filling per `LASSO_FILL.md`: seed the loop's ring, never leave `loopMask`, keep `loopMask ∧ ¬reached`. Circling a closed box paints 0.4004 of the canvas — its exact footprint — against 1.000 before. |
| **Cross eraser left stubs** | `StrokeGeometry.intersections` clustered in *sample-index* units against a `tolerance` that is a physical distance, so one crossing arrived as 25–109 entries and the bracket picked the worst. Stub measured 10.0 pt at 90°, 29.0 pt at 11°; **0.0000 pt** after. |
| **Cross eraser size did nothing** | The footprint now selects every stroke whose centreline it covers, each cut back to its own crossings, with a canvas-accurate ring drawn under the finger. |
| **A second fill broke the first** | Each gesture claims a `fillGeneration`; the worker carries an immutable context snapshot, so pairing a new seed with an old session is unrepresentable rather than merely documented against. |
| **Stroke interrupted by a menu** | One closed set (`CanvasPresentation`), one central rule, and `StrokeGiveUp.interrupted` so an interrupted stroke keeps its ink instead of being rolled back like a two-finger hand-off. |
| **Add Text** | Stage 1 complete: place, type, style, move, bake on a raster layer. |
| **Performance Tier A** | 5 of 7 shipped, 2 were already done. Gallery tile composites at the tile's size (41× less overdraw), timeline relayout gated on a key, `full` reused across a layer switch, mask cache wired to the memory warning, project open has a spinner. |

## What needs the owner's iPad

Nothing below is a doubt about correctness — all of it is proven headlessly. These are the things a
simulator cannot answer.

**1. Add Text, keyboard-over-canvas. This is the priority** — nothing headless reaches it, and it is
the likeliest place a real defect is hiding. In order:
   1. **Place a box near the bottom of the screen.** There is no `keyboardLayoutGuide` handling at
      all, so the box may sit under the keyboard. Most likely visible defect.
   2. Tap into a box, then open and close the text and colour panels. Watch for the keyboard
      dropping, or the caret surviving while the sliders stop applying.
   3. Zoom to ~0.3× and type — check the glyphs are not soft and the drag band is still the right
      size on screen.
   4. Scribble into the box with the Pencil, and drag-select inside it.
   5. **Record one `ActionRecorder` session covering 1–4** (Actions ▸ Record My Actions) and hand
      over the JSONL. Focus fights with the canvas's own recognizers are exactly the bug class it
      exists for.

**2. The lasso, on the two scenes the owner named**: a shape with a gap in its outline, and a loop
drawn well outside the shape.

**3. The cross eraser's feel**, for both rulings — the radius is now a real footprint and the ring
shows it.

**4. Is the app-switch freeze gone, or only smaller?** It is provably one save now instead of three,
and that save composites 41× fewer pixels. Whether one cheap save on the way out is still felt is not
answerable from here.

**5. Does leaving to the gallery still feel like ~3 s?** The thumbnail half is fixed. `PERFORMANCE.md`
§1 says the wait was never the thumbnail — it is the whole-document PNG re-encode, which scales with
cel count.

**6. The 2048×1024 vector-vs-raster preview number** (Tier B item 8). Device-only: a simulator figure
is worthless for GPU cost, and this repo's history is explicit about that.

**Deploy is blocked, not skipped.** `xcrun devicectl list devices` reported the iPad `unavailable`
all night. `~/.config/paintapp/.env` is present and the steps in `CLAUDE.md` are ready — run them
from the repo, not `deploy/deploy.sh`, which pulls `main` and so cannot ship branch work.

## What the owner owes a ruling on

New this pass:

1. **Should a lasso leak get its own signal?** The collar tint cannot show one — a leak still paints
   the outline, so it is not an empty result and the signal never fires. Detecting a leak properly
   means asking whether any ink component inside the loop encloses a region the collar walked into: a
   diagnostic-only connected-component pass, which `LASSO_FILL.md` §4 case 5 does not forbid because
   its ban is on the *fill* path.
2. **The cross eraser deletes a covered line that crosses nothing, whole.** That was always the rule,
   but the circle used to be a pinpoint and can now be 50 pt across — so one tap near a busy corner
   can also wipe a stray line entirely. Much larger undo step than a tap used to be.
3. **The cross eraser takes a stroke by its centreline, not its ink**, so clipping only the edge of a
   thick line leaves it alone. This makes the circle exactly the rule; the alternative makes it act
   slightly larger than it looks.
4. **A superseded lasso no longer says "nothing enclosed".** Draw a loop enclosing nothing, then
   immediately fill elsewhere, and you get silence rather than a banner about the loop you abandoned.
   Judged correct — the alternative attributes the message to the fill that replaced it — but it is a
   judgement, not a spec line.
5. **Which five or six faces belong in the font favourites strip** (`ADD_TEXT.md` §5 item 5). Shipped
   with all ~60–80 families grouped and **no strip**, because inventing a shortlist makes it the
   answer by default.
6. **Add Text `autoSize` caps at the canvas edge and wraps** rather than growing forever, because
   there are no handles until Stage 4 to drag a runaway box back. Right behaviour, or should a box be
   allowed to run off?
7. **The toolbar colour swatch changes meaning while a text session is live** — it edits the text's
   colour, not the brush's. Deliberate, but it is a visible change to a control used constantly.

Carried, still unruled:

- **Save semantics when a project loaded with something unreadable**: overwrite, refuse, or prompt?
- **A double-traced ellipse detects as a rectangle.** Pre-existing, verified, not a regression.
- **The smart oval has no arc-end handles**, so "I drew 100° and wanted 180°" means drawing it again.

## What is worth doing next

**`PERFORMANCE.md` item 9(b) is the new front-runner, and it was promoted by a measurement taken
while building Tier A.** On a playback tick the `@MainActor` snapshot costs **78.2 ms** against
**22.2 ms** of background composite — so `renderSources`, the same per-cel rasterize fan-out
`ProjectStore.load` runs serially, is now the largest main-thread term on the path. Item 4b (lazy
`below`/`above`) was **declined on that measurement rather than deferred on a risk**: it would trade
~11% of a tick, in the half that was never on the main thread, for a stroke whose first frames have
no visible ink. Revisit it only after 9(b) moves the snapshot off main and the table is re-taken.

Also open: Add Text stages 3–6 (vector layers keep it editable, then rotate/scale, then the
projective distort), and Tier B, which is instruments and mostly needs device numbers.

**Two costs of the menu fix remain, both deliberate and both pinned by named tests in `BUGS.md`.** An
interrupted stroke is still *short* — closing a popover a frame earlier does not stop the teardown
landing mid-sequence, and nothing recovers samples UIKit never delivered. And the touch that
discovers a stranded stroke is spent discovering it, so the *third* attempt is the first that draws.
Binding that touch instead means driving a recognizer's `state` from `.ended` back to `.began`, which
is undocumented and fails as "drawing stops working" rather than as a delay.

## Three things this pass learned the hard way

- **The docs can be two days stale and read as authoritative.** `PERFORMANCE.md` and `BUGS.md` both
  described the `scenePhase` triple-save as outstanding for two days after `1cbec5b` fixed it. A
  session trusting them would have rewritten a merged fix. Check `git log` for the file before
  building anything a document says is outstanding.
- **Concurrent agents share one scratchpad directory.** A fixed filename like `udid.txt` is silently
  overwritten, and one agent ran a whole suite on another agent's simulator. Nothing failed — the
  xcresult's `deviceName` field is what caught it. Read that field alongside the count.
- **A control test earns its keep on the first run.** The `Menu` measurement's first draft counted
  *raster* strokes on a layer that is *vector* by default, so it read 0 through the menu and would
  have reached the right answer for a reason that could not have been wrong. Its paired
  no-menu-open control failed and caught it.
