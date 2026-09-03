# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## Do this first — you are about to be given a design briefing, not a build task

**The owner is briefing you on TODO (26) import videos and TODO (37) import paintbrushes / brush engine
overhaul.** That conversation is the work. Read both entries and both "ask first" lists *before* it
starts, so you spend the owner's attention on decisions rather than on orientation.

**Do not start building from either TODO entry.** Every item under TODO's "Later" heading carries the
same entry condition, in the owner's words: *"When you get to these, prompt me to explain to you in more
detail how they work."* **An item built from its entry alone was built wrong** — that sentence is in TODO
because it happened. Your deliverable from the briefing is a specification document per item, the way
[KEYFRAMES.md](KEYFRAMES.md) exists for (21) and [RENDER.md](RENDER.md) for (29): the ask in full, then a
numbered section of the owner's rulings in their own words, then the design, then a build order. Those
`§2`-style ruling lists are the highest-value thing in this repo — four separate documents now say "read
these rather than re-deriving them", and passes have been lost to re-litigating a settled call.

**Read [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) before the (37) conversation.** Its
TODO entry says "unread this pass by instruction" — that instruction was scoped to the session that
received it, and the briefing lifts it.

**What (26) already has settled, so you do not spend the conversation on it.** Its dependency on (21) is
satisfied: it needs content that varies across the frames one cel spans, and stage 5's transform channel
introduced exactly that. It is the head of a chain — **(27) screen recording, which the owner calls "the
big feature", requires (26)** — so briefing it first is what unblocks the most. Two things to carry in:
`"video"` is currently the **sentinel** for "a layer kind nothing implements" in the forward-compatibility
tests, so implementing it takes that sentinel away and those tests need a new one; and a video element
inherits what Move stage 3c decided about `VectorImageElement` — a `LayerTransform` plus a stored
`aspect`/`stretchAxis`/`mirrored`, read back through `VectorImageElement.placement`.

**What (37) already has settled.** KEYFRAMES §2.16's declined half is this item's inheritance rather than
an open defect: a stroke you Move re-samples its grain, and the owner ruled on 2026-09-03 that it stays
that way until the overhaul, because grain is expected to change when brushes become importable. Do not
re-open it as a bug; fold it into the design.

**The four questions (26) cannot be built without**, all in its TODO entry: what "a specific length" means
when the cel's `frameCount` and the video's duration disagree — resize, retime, or refuse; whether
cropping trims or retimes; one video per *layer* or per *cel*; and at what rate a 30 fps source plays in
a 24 fps document.

**Nothing is owed before you start.** The fast tier is **2698 / 2695 passed / 0 failed / 3 skipped** at
`608386e`. The last full suite was at `04099a9` and now predates three passes that changed the
compositing sweep, the export driver, the cel-copy verbs and the whole keyframe marker model, so **a full
run is owed at the next phase boundary** — twenty-two minutes, and CLAUDE.md's triage section is what to
read before believing any red it produces.

**If the briefing does not happen and you need code work instead**, the order is: (1) Distort's ink tier
with KEYFRAMES 5b, together, both unblocked by stage 4 and sharing `DabPose.localScale`; (2) the three
small defects (32), (33), (34); (3) (31)'s last symptom — 16383² cannot be composited at all — with
`StripedCompositor.assemble`'s unbudgeted two-frame peak, same code; (4) (29) stage 7, the memory audit,
after PERFORMANCE §9's census is re-taken. The competing claim on (1) is the three gaps stage 5 left,
which are more visible to the artist day to day: Move is refused at a frame whose pose is not resting, a
pose channel has no graph-editor band, and animation groups have no UI. **That missing pose band is also
what stops (38)(c)'s rule being exactly true**, so it now has two reasons.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**Nothing is in flight. No worktrees, no `tmp/*` branches, nothing uncommitted.**

**Fast tier: 2698 total / 2695 passed / 0 failed / 3 skipped.** It was 2657 at the start of this pass.

**TODO (38) is fully merged** — frame gridlines, a keyframe and a graph node being one thing, bezier
tangent handles with the tap grammar that goes with them, and a value readout on a node drag. The one
thing to know: **the handle control the owner named did not exist** and was built to their confirmation
(in place on the graph, `.free` tangents, Reset Curve as the way back).

**Five owner rulings landed this pass and are recorded where they act**, not here: a node on the
graph and an indicator on the cel are **one thing**, which supersedes KEYFRAMES §2.28's closing rule; §2.16's grain-on-Move
decline **stands** and belongs to the brush overhaul, TODO (37); and a copy of an in-between is **a
flattened still**, which duplicate, copy and split now implement.

## RENDER (29) is delivered through stage 6; stage 7 is what is left

[RENDER.md](RENDER.md) is the specification. **§2 is sixteen owner rulings; read them rather than
re-deriving them.** §5 is the build order.

The app now runs on the bake. `Engine/FrameBakeKey.swift`, `FrameBakeStore.swift`, `BakeQueue.swift`,
`DecodedFrameRing.swift`, `FrameBaker.swift` and `StripedComposite.swift` are the machinery; the live
canvas at rest and playback are served from LZ4 files on disk, and the timeline shows which frames are
not yet ready to play.

**Stage 6, export, is MERGED.** The app exports an animation as H.264 `.mp4` and a frame as PNG, and
neither re-renders anything. The design that made it small: **an export is a scrub** — `BakeQueue.next`
was already a pure function of the playhead handed to it, so the export needed one field, a virtual
playhead (`FrameBaker.exportFocus`), and no second queue. Store eviction and ring warming follow from
the same local.

**Export is tested now, and writing the tests found two defects that are fixed in the same change**: an
`unowned` `CanvasManager` that aborted the process when an export unwound after the document closed —
`ContentView` replaces its `@State` manager on open/new, two taps from the sheet the artist just
dismissed — and a progress bar that ran backwards once per frame, because the video loop interleaves
bake and write while `fraction` modelled them as two consecutive halves. `FrameExportSessionLogicTests`
is 13 green on the driver and `ToolPanelsUITests` carries one XCUITest for row / progress / share sheet.
**What export still owes**: four failure arms with no fixture (`unreadableFrame`, the PNG write refusal,
`bakeFailed(.exceedsCeiling)`, the `VideoFrameWriter.Failure` sentences), the focus's two knock-on
consequences, and **nothing has run on the device**.
**The keep-the-bake option (§2.11) is deferred, not built**, with the stamp decided — the encoded-tier
hash, because a manifest stamp bumped from edit sites inherits every hole the sweep exists to cover, and
in a *persistent* content-addressed store a missed site is a wrong picture with no error. §3.9a carries
the reasoning and the two things beyond the stamp that a kept store needs.

Video is `AVAssetWriter` over the store in frame order, H.264 in `.mp4` at the document's fps and the
knob's resolution; a frame is the baked frame as PNG. **Both re-render nothing** — §2.1, and the whole
reason the store exists. Delivery is the system share sheet.

Then **stage 7, the rest of the memory audit** (BUGS.md's ranked sites plus PERFORMANCE §9): the
fill-session budget, blanked hosts, count-only caches moved to byte budgets, a `MemoryPressure` seam so
Android and Windows can signal eviction, undo cost for whole-cel raster steps, and `SaveSnapshot` off
the main actor.

**Small things stage 4 left behind**, each a few minutes:

- **`FrameBaker.reset()` is wired**, to `CanvasManager.closeFrameBaker()` from
  `ContentView.returnToGallery` — the document-closing case its doc comment named. `ContentView` keeps
  the `CanvasManager` in `@State` across a return to the gallery, so the baker's bookkeeping and its
  decoded-frame ring, up to 96 MiB, sat resident for a document nobody was looking at.
  **`markEverythingDirty()` stays, and "a straight delete" was wrong.** It is redundant for the app,
  confirmed — but `bakeQueue` is `private(set)`, so it is the only way anything outside `FrameBaker`
  can force a worst-case dirty mark whose *key is unchanged*, which is exactly the scenario
  `testAScrubThroughAHoldCostsNoComposites` pins. Both of its inputs are folded into `FrameBakeKey`, so
  triggering either for real forces a genuine recompute rather than the dedupe that test measures.
- The compression ratio on the owner's own **"UI Test"** document, and a decode against a frame the
  *compositor* produced rather than one drawn for the purpose. PERFORMANCE §10.4 records both as owed.
- **The whole of this pass is on the owner's iPad** — a Release build of `608386e` was installed
  2026-09-03. What is owed is their *confirmation*, not another deploy: that the resolution slider reads
  Full and the canvas is full on the "UI Test" canvas they reported it on; that export produces a video
  and a PNG on the device, where nothing has ever run; and that the timeline's amber bake strip and the
  new frame gridlines read at their working zoom.
- **`StripedCompositor.assemble` bounds the walk but not the destination**: it holds every strip's core
  in `pieces` and then draws them into one full-frame renderer, so the peak is about two frames with no
  budget consulted — roughly a gigabyte at 16383². Whether that is worth fixing on its own or belongs
  with the "16383² cannot be composited at all" item is an open call.
- **Nobody has measured playback end to end since stages 4 and 5 merged.** The decode figures are in
  PERFORMANCE §10; what is unmeasured is whether the baker keeps up with a scrub on the device, and that
  is the measurement that would reopen PERFORMANCE §8's 24 fps ruling.
- **PERFORMANCE §9's "still open from the twelve at `9c9d435`: all of them" wants re-taking.** Chunking
  closed part of audit item 1; the other eleven were not re-audited. The sentence names a commit so it is
  not false as written, but it is no longer a census.

## The review is closed: twelve defects fixed, one refuted, and the tests are the problem now

Every one of the thirteen candidates has been settled against the code. **Twelve were real and all
twelve are fixed**; the thirteenth — a Distort bake said to round a non-square crop into a stretch, and
the only one that would have reached a *saved* document — was a misreading. BUGS.md keeps the
refutation and the two places a fix differed from its sketch.

What they had in common is worth more than the list. The bake's dirty sweep is the one place in this
design where *"what reaches a pixel"* and *"what the differ compares"* are two hand-maintained lists,
and **four of the twelve were holes in it**: a pose edit, a folder's animated grade, an in-between's own
recipe, and an edit landing while a bake was in flight. The sweep now stamps the pose channel and the
recipe's content fingerprint on the cel, folders' tracks and the document's guides on the structure, and
`finish` re-mints before it clears a dirty bit. **The general problem is not fixed** — nothing holds
those two lists together, and the next field added to a `Cel` will be invisible to the sweep in exactly
the same way.

**The tests this pass added have now been read, and that is where the open work is.** BUGS.md's first
entry has it in full; the two that matter:

- **The bake key's completeness table covered three of its nine fields and is now closed.** Seven
  encoder lines were deletable with the whole suite green — including `rasterVersion` and
  `vectorVersion`, the two an ordinary brush stroke moves, and the only two. Each has a row that moves
  it *and nothing else*, so a deleted line collapses exactly the row naming it; the same pass covered
  every `StructuralStamp` field and the `maskStacks` sort. **The reviewer's claim that no fixture in the
  suite ever stamped a dab was too strong** — several do — but none of it reached the *key*, which was
  the load-bearing half.
- **The rest-space dab bake has no test that can go red.** All five pin
  `BrushStamper.DabPose.applied(to:)`, which copies `alpha` and scales `radius`, so every assertion is an
  algebraic consequence of that one function and true under any implementation — including one that
  walks in posed space and reintroduces the grain boil the stage exists to remove. The only test that
  reaches the shipped dispatch compares `opaqueContentBounds` at accuracy 2, and `VectorCanvas.posing`
  has already posed the samples and scaled `size` before `stamp` picks an arm, so reverting all three
  arms leaves it green.

**And a new way for a fixture to be wrong turned up, which is the one to carry forward.** The four found
before this pass all measured *nothing*. This one measured the *wrong level*: a passing test asserted
`blend(a, b, t: -0.4) == a`, which is true of the channel but not of `blend`, and it held a real defect
in place for the length of stage 5. The question that catches it is not "can this go red" — it could —
but **"if this went red, would the code be wrong?"**

## What this pass established, and would otherwise be re-derived

**On the store and the key**

- **A content-addressed disk store cannot be built out of this app's `Hashable` conformances.**
  `LayerContentVersion.hash(into:)` deliberately omits `effect` and is right to — every in-memory cache
  here compares `==` after the bucket lookup, so a collision costs one compare. A store whose filename
  *is* the digest has no second chance. `FrameBakeKey` is a hand-written canonical byte encoder: a
  discriminator per enum case, a length prefix per collection, floats by `bitPattern`, and **no
  `default:` clause anywhere**, so a fourteenth `Effect` case is a compile error rather than a silent
  collision on disk.
- **`COMPRESSION_LZ4` is not portable** and §3.5 chose it *for* portability. Apple's constant wraps the
  stream in `bv41` framing no other LZ4 decoder reads. It is `COMPRESSION_LZ4_RAW`.
- **The per-row Up filter §3.5 held in reserve loses.** MEASURED: it makes every fixture *bigger* (cel
  art +39%, hold +28%) and costs 4.3–8.9 ms each way against a 1.5 ms decode.
- **Decode tracks pixels, not file size.** A hold is a quarter of cel art's file and decodes *slower* at
  every size, so a ring budget must mean *decoded* bytes.
- **Measured on the owner's iPad 9 in Release**: cel art 54.4x–73.2x, holds 135x–151x, painted 1.49x,
  noise 1.00x (the raw-store branch). Decode 1.5–3.1 ms at the owner's canvas against a 41.6 ms frame;
  4096² worst case 24.6 ms, still inside a frame at 1.70x.
- **The simulator inverts that measurement.** Between Debug/simulator and Release/device the two halves
  of the decode moved in *opposite* directions — LZ4 8.9 → 1.4 ms, `CGImage` build 0.8 → 2.6 ms. Debug
  reads as "the codec is 91% of the decode"; the device reads as the reverse. PERFORMANCE §1's "device
  is ~1.3x the simulator" is a *compositing* rule and does not generalise.

**On the scheduler and the canvas**

- **There is no push funnel in this model that knows a frame.** `beginCanvasEdit()` runs *before* an
  edit; `recordUndo`'s stored closures bypass it on replay; and a dab lands in `VectorCanvas` /
  `RasterLayerTexture`, which are classes, so `@Published var layers` is never written. Dirty marking is
  a **sweep** — `syncDirty()` diffs the cel layout against the layout last seen, once per
  `reconcileLayers` pass. That cadence is an identity rather than an estimate: the passes that publish
  are exactly the ones that used to move `SandwichKey`.
- **§3.6's claim that `isSandwichRebuilding` is a drop-if-busy was wrong.** `finishSandwichRebuild` ends
  in `reconcileLayers()`, which re-derives the key and starts the rebuild the guard declined — it always
  was coalesce-and-retry. Deleting it hands a two-second scrub ~120 serial jobs.
- **§3.6's "same worker and same memo" is bought by the buffer size, not the queue.** `PixelOps.rasterize`
  and `MaskResolver.CacheKey` are keyed on width and height, so the bake mints at `.liveComposite`.
- **A ring top-up needs an outward-only marker or it does not terminate.** The ring is routinely narrower
  than the lookahead, so a plain rescan fills a far frame, evicts a near one, finds the near one missing,
  and never converges — while leaving the far end resident, which is backwards.
- **`isBaked(atFrame:)` could not serve the consumer §3.7 names it for.** It was a full recipe mint plus
  a `stat` — correct for one frame, and 300 × layers of it per redraw for a ruler. It is two dictionary
  lookups now, and **both halves are load-bearing**: an edit leaves `keyByFrame` in place, so the recorded
  key names a real file holding the picture from *before* the edit.

**On strips**

- **Strips nest outside chunks, and the nesting is forced rather than chosen.** A chunk hands its
  accumulator to the next chunk *in the same buffer*, so a chunk cannot span two strips. A strip is a
  whole self-contained composite of the entire tree over fewer rows. One budget account:
  `affordableRows` is `chunkSources` solved for height, and a strip that still does not fit is chunked
  with no special case.
- **§3.4's rule 3 does not generalise to strips.** It is dangerous for a *chunk* because a chunk discards
  sources; a strip discards none — it windows every one — so the `.ink` re-walk inside a strip is the
  window of the whole frame's, and the apron covers the kernel's reach past the band.
- **Two effects read absolute position and no apron can pay for them**: `noiseValue` hashes `gid`,
  `screenValue` indexes a Bayer cell by `gid.y & 3`. Both take a frame origin now.
- **Three memos are keyed on buffer size and collide across equal-height strips**, repeating one band
  down the canvas on an ordinary drawing with no effect, mask or blend. `MetalCompositor.UploadCache.Key`
  **has no CoreGraphics counterpart**, so the CPU suite was green on every fixture in the file while the
  GPU repeated a band.

**On the dab bake (KEYFRAMES stage 4, merged)**

- **A pure translation re-phases the dab walk** — 110 dabs or 111 depending on the frame. Nothing
  predicted this; §4.2's framing was about non-uniform maps and stage 5 had already found the Uniform
  arm reaching it.
- **`BrushLibrary.square` does not re-phase over an ordinary shrink** (spacingFraction 0.15 clears the
  1 pt floor to scale 0.278) while Pencil does on 24 of 24, so §4.2's "two non-round-dab cases" are one
  brush.
- **§2.16's "a stroke you Move keeps its grain" was declined rather than delivered.** A commit rewrites
  the stored samples, so the rest space itself moves; storing the multiplier would be ~8 floats per
  stored sample for a derivable value. **Put back to the owner and ruled: it stays declined**, and
  belongs to the brush overhaul, item (37) — grain is expected to change when brushes become
  importable, so it is that item's inheritance rather than an open defect.
- The fix was **one field** (`VectorStroke.restWalk`) plus a 15-line `DabTarget` decorator, and no
  change to grain code at all: wrapping the *sink* rather than the walk leaves `stampSpacing`,
  `applyScatter`, `grainAlphaMultiplier` and `stampApproximateSquare` running unchanged in rest space.
  Nothing went on the wire — `VectorStroke`'s hand-written coder names every key, so the field is off
  it by construction, and no migration was owed.
- **Per-dab projective width is now reachable**, which is what unblocks Distort's ink tier: `DabPose`
  returns nil for `constantScale` exactly when the map is projective and asks `localScale(at:)` per dab.

**On poses**

- **KEYFRAMES §8's prescription that a pose identity "must include the frame" is wrong.** What an
  identity owes is what `render` *reads*, and this render reads the resolved per-channel affines — the
  frame is what it reads them *through*. Carrying the maps is sufficient and **strictly tighter**: a
  frame field would mint a second cache entry for every frame of a `step: 2` hold and of the
  constant-hold tail, which is the cost §8's own parenthesis warns about, by the other door.
- **A pose channel needs no "stored base" field.** A value channel needs one because `Layer.effect` holds
  what a slider writes when nothing is keyed; a pose channel's base *is* the cel's geometry.
- **Grain boils under a pose** — `BrushGrain.noiseValue` is read in absolute canvas coordinates at the
  *posed* stamp point, so the texture crawls across the ink instead of travelling with it. §4.2's
  prediction, confirmed. Fixed by KEYFRAMES stage 4's rest-space dab bake, not before; the test is
  written to go **red when stage 4 lands**.

**On Distort**

- **Preview and bake are exact, not bounded** — one accessor feeds both, and `CATransform3D`'s `m14`/`m24`
  perform the same projective divide the bake does. MEASURED 0.0 disagreement over the box interior
  across ±3 rad and both mirrors. Strictly better than §5.17's Freeform latch, and there is no latch.
- **A projective `CATransform3D` draws correctly and hit-tests unreliably.** On an outline view it left a
  distorted piece reshapeable and then undraggable, with the corner grips still working. Only a UI test
  could have said so.
- **Distort reaches the raster floating piece only.** Placed images and text are lassoable solely through
  the vector float, whose map is a `CGAffineTransform`. Text already has a real Distort by its own door
  (Text panel → Corners). A **placed image** is the one kind with no door: six numbers plus a mirror bit
  where a homography needs eight.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do. The cap is **3 opus or 6 sonnet at once**
   (1 opus = 2 sonnet).
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned.
3. **A replaced path is deleted, not left beside the new one.** RENDER §2.15 in the owner's words:
   *"very clean and non-redundant, with no peculiarities, and no legacy code left by the previous
   functionality."*
4. **At most one investigation agent at a time.** Building is separate.
5. **Weighty programs may be killed to free the machine.** Standing permission.

## Traps this pass paid for

- **A brief's prescription is a hypothesis.** Fourteen were refuted this pass by the workers holding the
  code, and **five of those were errors in a specification** rather than in a brief. Invite the
  refutation explicitly; it is the cheapest review in the project.
- **A green assertion is only as good as its two operands**, and CLAUDE.md now has a section on it.
  Four fixtures measured nothing in one day: a per-field table that built a fresh `CanvasManager` per row
  and so compared `ObjectIdentifier` allocation addresses (it passed with the field under test **deleted
  from the encoder**); forty rows setting `layers[0].effect` on a raster layer when the render path reads
  `layerEffect(atFrame:)`, which is `kind == .value ? effect : nil`; a §2.16 fixture eaten by the very
  dedupe it was counting, because a cel spanning frames 2–6 *is* a hold and those five frames are one
  key; and a UI probe that matched the black letterbox because it tested *not-white* instead of *dark*.
- **Which pbxproj group a file goes in decides how its `path` resolves.** A test file placed in
  `App sources shared with PaintSoftwareUITests` — whose entries carry a full path from the project root
  — makes a bare filename resolve to `/Name.swift`. This surfaced as a missing *file*; the same misfiling
  one level down surfaces as a missing *symbol*.
- **The near-miss CLAUDE.md describes actually happened.** Two branches appended a test entry after the
  same anchor in `project.pbxproj`. Nothing had to be renumbered **only because both derived their ids
  from the file name** rather than counting off a neighbour.
- **`canvas.host` is itself an accessibility element**, so no descendant of the canvas can be addressed
  by identifier. Adding handle identifiers produces a dead affordance, not a testable one.
- **`xcodebuild` waits on "Unlock Kevin's iPad to Continue" rather than failing** — one run sat twelve
  minutes and then completed by itself. PERFORMANCE §9 had given up at that same wall.
- **Reading an xcresult chosen by `ls -dt` is not reliably reading the run you mean.** It cost one wrong
  "six tests are missing" diagnosis. Reconcile executed against a static `func test` count instead.

## Everything else open

**The owner's asks** are in TODO. (21) keyframes stage 5 and (12) LASSO_MOVE stage 5 both merged this
pass; what remains of each is written in their entries. KEYFRAMES §8's **5b is *animated* Distort** — a
quad keyed across frames — and is a different feature from the Move-box Distort that shipped; §2.13 makes
a pose a quad so the two meet with no migration.

**(31) is now one symptom, not three.** The resolution bug is fixed by strips and the `minificationFilter`
half is fixed; what remains is that **16383² cannot be composited at all** and needs a downscaled display
proxy.

(32)-(34) are small. (22), (24), (35)-(37) and (26)-(30) are unstarted, and the last group needs a design
conversation each.

**Deferred by the owner, not refused:** scaling the stroke sample gate by zoom, which would fix the 8x dab
explosion when zoomed out. It is a permanent quality trade, so it wants an A/B the owner can look at, not
a number.
