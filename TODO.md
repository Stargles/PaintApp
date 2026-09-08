# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

## How to read and keep this file

Every item is a **status**, a short **description** a future session can pick up cold, and **what is
left** as a checklist. Items are in **queue order** — the top of the list is what to do next.

**An item leaves this file when it is merged, not when a branch exists**, and it leaves *whole* rather
than being marked done: `git log` and the spec documents are the history. The owner, 2026-09-06:
*"Basically I want to be able to read the tasks on TODO clearly without already finished tasks."*

**Three in flight at once** unless the extras need no simulator — the cap is about the machine, not the
plan (`tools/simlock.sh`).

**Before adding an item, check whether an existing one already covers it in different words.** A
restatement filed as a new item is how one feature came to be specified in six documents at three
scopes before a line of it was written. This file has since carried two live duplicates for weeks.

**Record an ask in the owner's own words, and fold a ruling into the item it rules on.** A quote is
cheaper to keep than a decision is to rebuild. But an item reads as *one current description*, not as
the transcript of the argument that produced it — what happened this pass belongs in
[HANDOFF.md](HANDOFF.md) and in `git log`.

**Cite a symbol, not a line number.** A 2026-09-06 audit found ~10 of one item's 15 `FILE:LINE`
citations and 5 of another's 11 no longer resolved — every named fact still true, every anchor wrong,
two of them because a file moved directory. A symbol name survives a refactor and a line does not.

**A bare item number in a spec or a code comment may name an item that has already left this file.**
That is the merge rule working, not a dangling reference: `git log` and the spec documents are where a
completed number resolves. Two are cited often enough to name here — **(10a)**, the Oklab colour ramps,
and **(38)**, the graph editor's bezier tangent handles and their tap grammar. Do not re-add a finished
item to this file to make a citation resolve.

**Verify a status before trusting it, including this file's own.** That same audit found fourteen
assertions here that the code contradicted — features called unbuilt that shipped weeks ago, a blocker
called live that had lifted, and two commit shas that are not on `main`.

**No document written so far has to survive.** The owner, 2026-08-27: *"Don't worry about legacy
documents right now, everything on the ipad right now is expendable."* A format change needs no
migration and no "existing documents change appearance" warning. This is standing permission, and it
lapses the day the owner starts keeping real artwork in the app — whoever notices that should say so
rather than assuming it still holds.

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure taken before 2026-08-17 was at 4096², eight times the pixels.

---

## (36) Store projects in a folder the artist chooses

**Status** — **fast-tracked out of Later by the owner 2026-09-07**, who gave the reason: every test
build that lands on the iPad takes their saved work with it.

> *"Every time a test build gets uploaded to Ipad currently, everything is wiped. Thus, this task
> should be fasttracked out of long term. It should ideally behave just like any other programs file
> storage/save. It has a default folder storage location where it stores the files, but they can be
> changed. I'd like the option to organize the files into folders. May be helpful for organizing
> things into projects, sequences, scenes, shots, etc."*

**This is a data-loss item, not a convenience one.** Projects live in the app's own container today
(`Documents/Projects`), which is exactly the thing a reinstall is entitled to replace — and on
2026-09-07 a measurement pass wiped that container outright, destroying the owner's `AnimationTest`
document with no recovery. A chosen folder puts the work **outside** the container, where a build
cannot reach it.

**No dependency remains.** The stated ordering was counterfactual: RENDER stage 6 shipped without a
chosen folder by delivering through `ShareLink`. `BrushStorage` already documents the security-scoped
bookmark seam this needs, and `BrushStorage`'s relocatable storage is a worked example of the same
pattern at a smaller scale.

**Built 2026-09-07, all four parts.** `ProjectLocation` owns one root that
`ProjectBackupManager.documentsDirectory` reads, resolved before anything reads it; the gallery browses
an arbitrarily deep tree with breadcrumb, create/rename/delete and **Move to...**; migration is copy →
verify → atomic rename → remove, per item, so **every project is complete in at least one root at every
instant**; and the reinstall test asserts the defect first (a container project destroyed, the gallery
empty) and then the fix.

**Two limitations, both deliberate and both recorded rather than hidden.** The **bookmark does not
survive a reinstall** — it lives in the defaults plist, which is inside the container — so the artwork
survives and recovery is exactly one trip through the picker, which the test pins as one. And
`restoreFromTrash` returns a project to the **top of the tree** rather than its original folder;
Files-style restore-to-origin needs an origin marker on the trash entry.

**A hole in the `-resetGallery` guard was found and closed by this work**: the flag resolves its three
directories *through* `ProjectLocation`, so on a device that had adopted a folder it would have reached
outside the container and deleted the real library. It forgets the bookmark before wiping now, which
makes it container-only by construction.

**Left to build**
- [ ] `restoreFromTrash` to the original folder, which wants an origin marker on the trash entry.

---

## (54) A held frame may be re-rendered once per frame instead of once

**Status** — reported by the owner 2026-09-07, unverified. **They are right that the answer matters
more than the saving.**

> *"Lets say a frame in the animation is held for a couple cels where nothing changes. The bake and
> cache seems to re-render each frame even though they are the same. It is a simple optimization and
> not a high priority one, but if the program was not already meant to do this, then it could surface
> a deeper issue."*

**The design says it is already meant to do this**, which is what makes the report worth chasing rather
than filing as an optimisation. [CLAUDE.md](CLAUDE.md) states it plainly while warning about a fixture:
*"that cel **is** a hold, so those five frames are one bake key and one composite."* `FrameBaker`
carries a `dedupedCount` and an explicit dedupe path whose comment reads *"a dirty frame whose
recomputed key already has a file..."*.

**So the question is where the dedupe happens**, and there are two answers with very different
consequences. If the key is recomputed and the **composite is skipped**, the design holds and the owner
is seeing something else — a progress count, or the bake queue enumerating frames it then skips. If the
composite **runs** and only the disk write is skipped, then the expensive half is not being saved at
all, and every hold in every document pays full price. That is the deeper issue the owner suspected.

**Left to build**
- [ ] Establish which of the two it is, by counting composites rather than by reading the code —
      `CompositeProbe` counts calls to `Compositor.composite`, and note it counts **chunks, not
      frames**, so pin "one small frame is one composite" separately before trusting a total.
- [ ] If the composite runs, skip it and pin a hold at one composite for its whole span.
- [ ] Either way, say in RENDER.md which it was, because the docs currently assert the good case.

---

## (41) Mid-list edits and two kinds of undo that still re-stamp the whole cel

**Status** — partly built, and **the owner has accepted where it stands**: *"Honestly it isnt that
bad so it can be marked as done."* What is left is real but is nobody's priority until it bites again.
The general undo/redo work shipped 2026-09-06 (PERFORMANCE.md §11.11a);
what is left is two cases that are blocked on something a rectangle cannot fix.

> *"Undoing and redoing while there are a lot of strokes can be laggy, a few hundred milliseconds
> sluggish."* — 2026-09-06, after a first fix landed too narrowly

**What the artist is waiting for was measured rather than reasoned about, and it settles the shape of
the complaint.** The main-thread span of an undo press is **0.44–7.84 ms** across 200–4,000 strokes;
the render it causes is **5–2,275 ms**, 96–99.7% of the wait, and off the main thread. So the app
never stops responding — "laggy" is the old picture standing there. The **raster** arm is 0.02 ms a
press at both 2048x1024 and 4096² and needs nothing at all.

**The redo was 5.6–11.3x its own undo on the same one stroke**, which is the commonest pair of presses
in the app, and this item had written that off as permanent. It was wrong: the ink coming back *had*
been drawn, immediately before, by the walk that measured it. `VectorCanvas.vacatedInk` keeps that
measurement while the id is out of the list. MEASURED in Release: a redo at 1,000 strokes **571 →
51 ms**, at 4,000 **2,275 → 171 ms**.

**Left to build — and note this item's earlier "there is no design left to do" was wrong twice.**
- [ ] **A departing fill, image, text object or video forces `.everything`** whatever rectangle the
      caller passes, because `renderLocalContent` measures no footprint for those kinds. So the undo of
      a fill and the undo of a text commit still pay the whole cel, while their redos no longer do.
      The fix is to measure a fill's path bounds into `paintedBounds` — exact, unlike a dab walk — and
      teach `restoreDamage`'s departing loop to accept it. A text object's glyph extent and a placed
      image's quad are the same question.
- [ ] **A rewrite in place cannot be bounded by this mechanism at all.** Recolour, Apply Brush, a text
      re-edit, video crop and speed, motion-group retags, `keyPoseRestoringRest`, and **every
      lasso-move nudge** — `drawn(_:through:widthScale:)` preserves an element's id by explicit design.
      Only Recolour, Apply Brush and the text re-edit actually declare `.rewritesInPlace` (through
      `registerVectorElementsUndo`); video crop and speed, motion-group retags,
      `keyPoseRestoringRest` and the lasso-move nudge still call `bumpVersion()` directly in their own
      undo closures and were never touched by this pass. Either way it is the honest state and not a
      fix. Bounding them needs a different idea: an id whose *content* changed needs its old footprint
      forgotten and its new one bounded, and no rectangle from a caller supplies that.
- [ ] **The four call sites with the tightest rectangles are exactly the ones whose departures are not
      strokes**, which is why the "measure what was replaced" recipe never reached them.

**Blocks** (42). **Spec** PERFORMANCE.md §11, §11.10, §11.11, §11.11a.

---

## (21) Keyframes — four stages and four gaps

**Status** — partly built. Stages 0, 1, 2, 2b, 3a, 3b, 4, 5, 5a, 5b and 8 are merged; 6b was delivered by
(29); there is deliberately no stage 9.

A cel or an animation group carries a track of quad poses, ink is posed through the `sqrt(|det|)`
width rule with endpoints bit-exact, a pose channel has a six-curve graph-editor band that is
read-write, a transformation layer is reachable and usable, animation groups can be named, and every
pose key has a node.

**Left to build**
- [ ] **Stage 7 is half shipped, and the half that is left needs the owner.** Merged 2026-09-07: the
      editable fps (clamped 1-60, presets, live during playback, no undo step, persisted) and the live
      take on **the slider surface** — captured at the control's own rate, resampled at `fps`,
      deviation-simplified, landing as one curve and one undo step, with five refusals and two
      auto-stop paths. 35 mutations, one survivor found and fixed.
      **§5 specifies *"one mechanism, two surfaces: a slider, and the Move box"*, and the Move-box
      surface is not built** — `ValueRecording` is scalar-only while a transform channel stores
      `PoseQuad` keys, so resampling and tolerance both need definitions nobody has ruled on. §5's
      *"slow motion is a capture-speed multiplier on the record control"* is also unbuilt. **Both are
      owner-facing design and want a conversation before anyone builds them.**
      **One thing for the owner's eyes rather than a defect**: at 24 fps a new document's take is over
      before a person can react, because §5 runs a take over the scene you have. That is the design.
- [ ] **Stage 10**, the timing recorder (§7), which sits on stage 7 and was left until its base is
      whole.
- [ ] **Stage 6, bake to cels**, parked by that same ruling rather than dropped. It is cheaper than
      when it was planned — it shares its frame-walker with RENDER (29), which shipped, and the video
      bake merged 2026-09-06 is the same shape of operation with a worked pattern to copy. §6.
- [ ] A folder's pose channels are modelled and drawn but **cannot be opened into a graph band**,
      because `graphBandExpansion` is keyed by `layerIndex` throughout. Widening it to a
      `KeyframeTarget` is a stage, not a row — surfaced by the folder-transform work, KEYFRAMES §11.7.
- [ ] **Animation-group membership editing needs a design conversation first — but not the half the
      owner remembered.** Asked on 2026-09-07 they recalled ruling *"if you make a selection and try to
      move an already existing animation, then it refuses"*, and **that shipped on 2026-09-03**: §2.29,
      a Move catching part of a group is refused and says so. What is still open is **retagging** an
      element into or out of a group, which is the same question from the other side. §2.29 rules that
      splitting one animated group into two is *"a different feature"*, and retagging an element is
      that question from the other side — every key on both groups' tracks changes meaning.

**Spec** KEYFRAMES.md — **§2 is thirty owner rulings and §8 is the build order.** Four rulings
are superseded and kept; the file says which.

---

## (31) A 16k canvas crashes on a brushstroke, and cannot fit the owner's device at all

**Status** — **reopened 2026-09-07 by the owner**, who reports the app *crashing on a brushstroke* at
16k. The ruling on what to do is delegated: *"I don't know, you take the reigns."*

**The arithmetic settles it and no optimisation changes it.** The owner's iPad is an **iPad (9th
generation), `iPad12,1`** — MEASURED from `devicectl` 2026-09-07 — which has **3 GB of RAM**. One
16383² RGBA texture is **1.07 GB**; the compositor's sandwich needs **three**, so **3.22 GB**, on a
3 GB device. A 16k canvas cannot be held, let alone composited.

**This item's previous "the 16k crash is fixed" was measured on the wrong hardware.** That figure
(283.1 MB → 4.42 MB a gesture) is a *gesture delta* on a simulated iPad Pro with 8 GB, not the
resident cost of the canvas, and every simulator in this repo is an M4/M5 with 8 GB or more. **Every
memory claim taken on a simulator is suspect on the owner's actual device by a factor of at least
two and a half**, and that generalises well beyond this item.

**The decision, 2026-09-07 — lower `maxCanvasExtent` rather than build a display proxy.**
`CanvasManager.maxCanvasExtent` is `16383`. A downscaled proxy does not save it: the *stroke* path
still allocates full-size textures, which is exactly when the owner sees the crash. The owner works
at 2048x1024 — 8.4 MB a texture, three orders of magnitude below the cap — so nothing they do is
affected by a lower ceiling. Set it from a **measurement on the owner's own iPad**, not from a guess.

**Two of the three original symptoms are genuinely fixed and stay closed**: the resolution knob is
obeyed (`CompositorBudget.affordableSize`, `budgetTextures` and `CompositorSizeGate` are deleted, and
`StripedComposite` composites at the size asked for, pinned byte-for-byte on both backends), and the
freeze after a stroke lift is gone.

**Built 2026-09-07, except the measurement.** `maxCanvasExtent` is **4200** — INFERRED, derived in
PERFORMANCE.md §15 from four canvas-sized buffers (the sandwich's three plus
`RasterLayerTexture.ensureContext`'s), a x2 realism factor taken from `CompositorBudget.hasHeadroom`'s
own documented rule, and half the MEASURED 1837 MiB at-rest budget. That spends **58.6%** of it;
5486 is exactly break-even and 16383 is **892%**, which is the crash. 4096 was the first choice and
was rejected because it collides with **nine** unrelated constants that independently land there.
The picker now says why a size is refused instead of clamping silently, and the test asserts the
recovery as well as the refusal.

**The actual mechanism is narrower than "unbounded memory", and worth keeping**: `StrokeScratch` was
already windowed by an earlier pass, which is why the old 4.42 MB fix never touched this crash. The
cost is `RasterLayerTexture.renderToUIImage()` forcing a resident canvas-sized `CGImage`, and **the
live sandwich rebuild is never budget-checked** — `CompositorBudget.hasHeadroom` has two call sites,
neither on this path, and a GPU-preferring document falls back to the same unguarded CoreGraphics path
when Metal declines.

**Left to build**
- [ ] **Confirm the constant on the owner's iPad** — PERFORMANCE.md §15.5 names the run: raise the cap
      locally, draw one canvas-crossing stroke at 4200 / 5486 / 6500 / 8000 / 16383 on a fresh
      single-layer document and binary-search the boundary; then repeat on a document with layers and
      undo history, which is the case the derivation is weakest on. Set it from the smaller run, with
      margin below the observed boundary rather than at it.

---

## (42) Editing the strokes inside a selection, not just their colour

**Status** — not started. **The owner set the order 2026-09-07: (41) first, then this.** Its
prerequisite got harder rather than nearer. A slider tick on a
selection is a *rewrite in place*, which is precisely the case (41) established cannot be bounded by
the damage-rectangle mechanism at all — the element keeps its id, so no rectangle from a caller says
which footprint stopped being true. This item needs that solved first, and it is a different idea from
the one that made undo cheap.

> *"i plan to replace the change color of selection into a better tool where you can also change the
> brush type, size, etc. of the strokes inside the selection. The color changer also shouldnt be the
> current selected color, but instead show the color picker menu defaulting to the current color. all
> changes able to be seen live in the drawing."*

Half of it shipped: the Select panel's **Brush** button re-points a selection at a brush as one undo
step (BRUSH.md §2.10), and `applyBrushToSelection`'s own doc says size, opacity and colour are
deliberately untouched and points back here.

**The live requirement is the load-bearing one and it has a hard prerequisite.** Adjusting a selection
rewrites elements in place, so every tick of a slider is a mid-list edit — a whole-cel re-walk is
~142 ms at the owner's density and 745 ms at 1,000 strokes, so a slider driving one is unusable.
**(41) is a prerequisite, not an optimisation.**

**Left to build**
- [ ] Brush kind and size at selection scope, alongside colour
- [ ] A colour **picker** defaulting to the strokes' current colour, rather than applying the palette's
      current one blindly
- [ ] Preview-then-commit so a drag previews without an undo entry per tick and commits once

---

## (22) Select multiple cels at once

**Status** — not started, and **deprioritised by the owner 2026-09-07**. The menu row exists and is `.disabled(true)` with an empty action; no
cel-selection state exists. The keyframe half of the same idea is real and shipping.

---

## (10) Linear light as an option on the blend mode

**Status** — not started, and **deprioritised by the owner**.

No colour-pipeline setting, no sRGB/linear enum, no transfer LUT, no `Composite.metal` change.

**One adjacent strand did ship**: `ColorMath`'s sRGB↔linear and Oklab conversions feed the gradient
map, which is this item's own "Oklab still gets built, for interpolation" half. The code calls that
**(10a)** in eight places, corrected 2026-09-07 from a stale count of nine — `Effect.gradientTable`,
`EffectSection`, `ColorMathOklabLogicTests`, `EffectParityLogicTests` and `tools/oklab_ramp_ab.swift`
among them. It is finished, so it left this file by the merge rule and the citations stand; see the
convention above.

---

## (37) The brush engine — one stage, and the owner has dropped it

**Status** — stages 0 through 11 merged. **Stage 12, the importers, is dropped for now by the owner**
(2026-09-06: *"skip the importer for now"*), so there is nothing actionable in this item today.

Twenty brushes in five groups with every asset generated and no third-party content; opacity and flow
split with a per-stroke buffer; canvas-anchored texture; the brushes menu and the full-screen editor
with orderable module chains, noise octaves and second inputs; relocatable storage; two-axis scatter.

**Left, when the owner wants it**
- [ ] Stage 12 — the `.abr` / Procreate `.brushset` / Clip Studio `.sut` importers. All three are
      undocumented and reverse-engineered, so the stage opens with a survey against real files, not
      with a parser. Test files are a real dependency. §2.21 makes it an **adapter** onto §6's
      modulation matrix rather than a bitmap reader.

**Owner-side, not ours**: their tuning pass over the other nineteen presets, and driving a real Pencil
to exercise tilt, which no test here can reach. BRUSH.md §13 has **nine** genuinely open questions
(recounted 2026-09-07 — the sixteen bullets split seven answered/closed, nine still open; the "eight"
recorded here was a miscount on the day this line was written, not later drift). Three of the nine
were offered on 2026-09-06 and declined; which three is not recorded here and could not be verified
against a transcript this audit does not have.

**Spec** BRUSH.md — **§2 is thirty-three owner rulings.**

---

## (45) Prune the repository into a state that can be read

**Status** — partly done. Named by the owner 2026-09-06:

> *"A lot of things are messy right now, so it may be worth sifting through to prune, organize, and
> just get the repository in a completely clean and up to date state at some point."*

This file was the first slice and is done. The 2026-09-06 audit that produced it found the same rot in
the specs, so the scope is now known rather than guessed — and the four checked boxes below were the
slice that needs no simulator. **Two of those four were already true when the audit wrote them down**,
which is the same failure the audit exists to catch, pointed at itself.

**A quarantine audit on 2026-09-07 (branch `tmp/prune`, five commits) checked every claim the four
already-checked boxes and the branch's own commits made, then rebased onto `origin/main` and
re-checked again.** Nothing in the branch was found false; two small pre-existing numeric errors were
found and corrected in passing (this file's own (10)-and-(37) counts, above and below) along with nine
drifted `FILE:LINE` citations in ARCHITECTURE_REVIEW.md's finding 3, two more in its finding 4, and
finding 4's own miscounted "twelve of sixteen" (it is twelve of seventeen). The
rebase carried real content: `origin/main` had independently shipped `LayerFolder.transform`'s
options-panel entry and pose-node delete/tap-to-add (both were still listed as unbuilt in this
branch's stale copy of item (21)) and had reopened and rewritten item (31) around the owner's own iPad
having 3 GB of RAM. All eight of this file's numbered items — (53) through (37) at the time, now seven
since (53) shipped and left the queue during the rebase — were re-verified line by line against the
rebased tree; every remaining status line and "Left to build" bullet checked out.

**Left to build**
- [x] **Fix what the specs assert that the code contradicts.** RENDER.md §5 stage 6 said the export
      driver was untested with no XCUITest; `FrameExportSessionLogicTests` is 13 tests and
      `ToolsAndSelectionUITests.testExportIsInTheActionsMenuAndRunsThroughToAShareableFile` drives it,
      so only `ExportSheet` and the device run are still owed. BRUSH.md §12 stage 2 had no DONE marker
      and §9.1's row was the only one in that table not struck through; all five names are absent from
      the app target and the two that survive — `noiseValue`, `supportsCleanCut` — are different
      tenants. **The third known item was already false**: neither `SelectionModels` nor LASSO_MOVE.md
      cites the lifted blocker any more, which is this list going stale in the direction of looking
      unfinished. Sweep the rest of the specs the same way — that is the last checkbox here.
      **One more is known:** VIDEO.md §2.10 closes by saying a baked video's images *"split like any
      other ink, because by then it is ink"*, and they do not — `splitForLassoMove` refuses `.image`
      exactly as it refuses `.video`, by centre and whole. Stage 8 recorded it in VIDEO.md §9 with the
      two ways to make the sentence true rather than picking one.
- [ ] **Citation rot.** ~10 of one deleted item's 15 anchors and 5 of another's 11 had drifted, two
      because a file moved directory. Sweep the specs the same way and prefer symbols to line numbers.
      **Partial pass, 2026-09-07**: swept ARCHITECTURE_REVIEW.md's finding 3, the section this branch's
      own `dc3834d` re-affirmed as "kept as written... still accurate" — the prose was accurate but nine
      of its ten `FILE:LINE`/name anchors had drifted (`ProjectStore.swift:507→587` and three
      failure-return lines, `:751→948`, `:799→1000`, `ProjectManifest.swift:376→490`,
      `ProjectBackupManager.swift:471→477`, and `BUGS.md:131` replaced with the entry's own heading —
      only `ProjectBackupManager.swift:460` was already right), now fixed. Finding 4's two
      (`ProjectStore.swift:160→185`, `ProjectManifest.swift:242→304`) were dropped rather than
      repaired, since the symbol is already named in the same sentence — "prefer symbols to line
      numbers" applied rather than just restated. The rest of the spec corpus — RENDER.md, KEYFRAMES.md,
      LASSO_MOVE.md, CANVAS_RESIZE.md, LAYER_TRANSFORM.md, VIDEO.md, EFFECT_BACKDROP.md,
      VECTOR_INTERPOLATION.md, LASSO_FILL.md, BRUSH.md, ADD_TEXT.md — is unswept.
- [x] **Dangling references.** Neither was rot. (10a) and (38) are **completed** items whose numbers
      survive in several citations each — (10a) in eight, corrected 2026-09-07 from the nine recorded
      here; (38)'s six was not re-verified, since a bare "(38)" also matches unrelated numeric literals
      and re-counting it needs more care than this pass gave it. The convention note at the top of this
      file says so, and item (10)'s text no longer leaves the question open.
- [x] **Two commit shas cited in this repo's docs are not on `main`** (`2fa1725`, `83f7c0d` — pre-rewrite
      orphans). Both are gone: this bullet was the only remaining citation of either. Sweep for others
      when the spec sweep above runs.
- [ ] Decide whether BRUSH_ENGINE_EXTENSIBILITY.md and REFACTOR_BASELINE.md still earn their place.
      **Recommendation, 2026-09-07 (not acted on — the owner's call): keep both.**
      BRUSH_ENGINE_EXTENSIBILITY.md is not orphaned — BRUSH.md's own header calls it "still accurate
      about the seams" and says its ordering "survives into §12", §11 says its argument is "not to be
      lost", and it is cited live from ADD_TEXT.md, KEYFRAMES.md, CANVAS_RESIZE.md and one production
      doc comment (`TextObject.swift`). Its own stale parts (the pre-§12 "Order, if it is ever
      scheduled") are already self-marked DONE or deferred to BRUSH.md §12, which is the existing
      convention for a survey a spec has overtaken — deleting it would orphan seven live citations for
      no gain. REFACTOR_BASELINE.md is also live-cited three times (`ARCHITECTURE_REVIEW.md`,
      `TimelineAndUndoUITests.swift`, `PerfBaselineTests.swift`) for specific numbers, so it should not
      simply go — but unlike the brush document nothing has re-affirmed its figures recently, its
      "Full suite, wall clock" row (541-1231s) is from long before the thousands-of-tests, 18-36-minute
      runs CLAUDE.md now tracks, and its "Known remaining costs" §1 cites an `invalidate()` API that no
      longer appears in `StrokeSpatialIndex.swift` under that name. It wants a re-measurement or a fold
      into PERFORMANCE.md as a dated historical baseline, not deletion — flagged for the PERFORMANCE.md
      agent rather than acted on here.
- [x] The stash stack is empty. It held **two** entries, not the one this bullet recorded: the
      2026-08-14 vector-interpolation snapshot (48 files, 134 commits behind, superseded by interp
      phases 6-7) and a 2026-07-21 pre-rewrite working tree (5 files). Both were labelled cleared with
      the owner's approval and neither had been dropped. The owner ruled to drop both on 2026-09-06;
      their SHAs are `1b8845c` and `2e4e2ff` in that commit's message if either is ever wanted back.
- [ ] Re-run the 2026-09-06 audit itself. It found fourteen false assertions in this file and a dozen
      more across the specs; a session that shipped this much will have introduced its own.
      **Partial re-run, 2026-09-07**: this file's own numbered items — all eight live at the time
      ((53),(41),(21),(31),(42),(22),(10),(37)) — were checked line by line against the rebased tree.
      One had already been fixed and left the file entirely ((53)); the rest needed no correction
      except the two counts fixed above in (10) and (37), both pre-existing and both off by exactly
      one. The specs were not swept beyond ARCHITECTURE_REVIEW.md's finding 3 (see the citation-rot
      bullet above) — README.md, KEYFRAMES.md's header and §9, and BRUSH.md's two cited claims that
      this branch's own commits touch or introduce were separately checked against the code and held
      up. A full sweep of every remaining spec is still owed.

---

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(27) Screen-record the computer as a layer.** Requires (26). The app does have `Transferable` and
  `UTType` now; what is genuinely absent is the *drop* gesture — no `onDrop`, `dropDestination`,
  `NSItemProvider` or `fileImporter` anywhere.
- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met — (29) shipped in full on 2026-09-06.
- **(35) Advanced masks** — colour-range masks and a colour-reassign blend mode. `MaskSource` has two
  cases and there are 25 blend modes with no reassign.
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
