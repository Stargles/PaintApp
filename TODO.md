# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

**Session 49 (2026-10-14):** the owner asked to continue through every actionable item, stopping only
for genuinely required input or context degradation. Agent count is unrestricted for now; usage
conservation and output quality take priority over speed. Use focused delegation and cheaper models
for routine work, with occasional queue reports. The owner asked to work independently while asleep
until 10 a.m. Toronto time. Raster scope and fixed exterior pixels for vector selections are ruled below.

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

**Old files are repaired once, never read forever.** The owner, 2026-10-10, retiring the earlier "no
document has to survive" permission now that real scenes live in the app: *"I will still keep the rule of
no legacy code. If an update causes existing files to be outdated, then they should be automatically
repaired by a throwaway script the session makes."* So a format change ships with a **one-shot repair**
that rewrites the owner's existing files (Projects, Backups, Trash) to the new format at launch, and the
app's decoder knows only the current format. The repair is deleted, whole, once the owner confirms
their files are repaired. Build `2974b33` broke this rule and lost the owner's keys (TODO (153)).

**The measurement baseline is [PERFORMANCE.md](PERFORMANCE.md) §1, not here**: the owner works at
2048x1024, and every figure taken before 2026-08-17 was at 4096², eight times the pixels.

---

## (178) Liquify tool

**Owner availability, 2026-10-15:** the owner is using the Mac and will say when finished.
Defer performance measurements until that notification; continue source review and correctness
checks without treating contended timings as qualification.

**Combined checkpoint (2026-10-15):** root integrates material `72f686f`, raster
`ae40f66` and sampler `effb239`. Material55/55, prior raster109/109, sampler native Debug20/20 and
Release21/21, and raster landscape UI8/8 passed. Linked Release UI1/1 proves exact cold reopen
and live source following. Three raw landscape screenshots were inspected. Final combined gates and device checks remain.
HANDOFF names current owners and exact evidence; this item remains open until merged.

**Exact-map batching (2026-10-15):** existing fan-out now shares one immutable prepared field
across disjoint points/row strips; no new worker framework or cache. Baseline Debug34/34 passed,
three committed-baseline faults caught132 intended diagnostics, and sources are restored. The18-fixture native benchmark and five actual Debug production windows
match every serial reference byte. The long Debug run was then cancelled (patterned batching202.6s
versus scalar90.9s); final optimized Release cost decides whether batching stays.
Four external alternating C++ pairs preserved84,956 source Doubles and179,020,536 evaluations exactly;
contended batch1.62–2.29seconds versus serial5.39–8.66 is not native/device qualification. Quiet
Release and physical first-use costs remain open. Evidence:
`~/PaintWork/evidence/s49-liquify-row-batches/` and `~/PaintWork/s49-liquify-logs/combined/batches/`.

**Required-picture refusal review (2026-10-15):** shared settlement now reports failure through
save, Move/Duplicate/Bake, resize, frame/layer/tool changes and other mutation boundaries. Actual
posed scratch alpha and direct frozen window failure are fixed and mutation-tested. A new native
pre-fix proof found transparent substitution and partial pictures on material refusal (19 intended
diagnostics across full/fitted rendering and actual consumers). The non-fallible PixelOps wrapper is
removed; actual callers retain prior thumbnail/onion/live pictures and refuse destructive copy work.
Unavailable recipes remain distinct from failed required pictures. Restored110 logic plus five raster
UI methods and deliberate fault proofs are next. A direct live-view headless assertion could not
compile because the view is absent from that target; removed and never counted. That small guard
receives source review plus the actual eraser UI, without a duplicate rendering helper or test seam.

**Follow-up review (2026-10-15):** the live view still advances `baseDocumentVersion` before a
successful picture. With a live stream, that false coverage claim suppresses every later retry of
the failed edit. Capture document coverage with each request and publish it only with its accepted
picture. Move also clears held ink and latches after its required hole render fails; its isolated
piece uses nil for both absence and refusal. Make latch admission require complete pictures and
use the existing float rollback on failure. The existing oversized native-material fixture passes
Move's geometry-only bounds checks, so this is a reachable caller gap, not an allocation hypothesis.
Preserve legitimate empty/eraser-only pieces and existing stream/no-render behavior; no new renderer.

*"It should be placed to the left of the brush tool in the top menu. When selected, it acts sort of like
a brush (you can control the brush type, size, etc), and otherwise it does basically what a normal
liquify tool does. The opacity slider turns into the liquify power, and the brush type also controls the
liquify tool's power, so for example if the streaky brush is selected and the liquify tool is applied at
a line, it sort of liquifies only parts of the line. One thing, All the liquify tool needs to do is
adjust the position of stuff. It doesnt need to simulate blending, distortions, and all that."*

**Ruled 2026-10-12**: it pushes **raster and vector** layers (vector strokes have their points moved
and stay vectors; text, images, video and streams are left alone); modes **Push, Pinch/Expand and
Twirl**, chosen in the tool's panel, all of which only move things; it acts on the **active layer only**,
and an active selection limits it further. This reverses the 2026-08-22 ruling quoted in
`TransformMode`'s doc ("Warp will not be a feature (like liquify)").

**Shape** (survey §C): each dab of the unchanged brush walk becomes a displacement, so tip, texture,
flow and hardness are the strength field for free. Its brush type, size and power are a third
`ToolProfile` — a `StrokeTool` case and a `ToolProfiles` field, which (176) built for it.

**Ruled 2026-10-14:** *"Include linked in-between frames now."* Liquify must reshape generated frames
while preserving their links to the source drawings. `VECTOR_INTERPOLATION.md` §3.8 specifies a
recipe-owned rest-space displacement field, never per-vertex offsets or `localEdits`; build that field
alongside the editable-drawing tool. The session-48 survey's proposed refusal of derived frames is
superseded by this ruling.

**Raster scope ruled 2026-10-14:** *"Move all raster pixels; leave editable objects alone."* Old raster
cels mix imported pictures/text, fills and moved paint in `bakedImage`, without origin/type information.
Liquify therefore moves every raster pixel in the active layer, including that flattened content;
separately editable text, picture, video and stream objects remain untouched.

Material queries, exact exterior opacity/paper, the complete replacement union, and translated
vector scratch backing are fixed and have restored native/fault proof. Linked-frame cold UI now
passes; its earlier apparent refusal was a slow Debug producer, followed by a stale gallery-name
precondition. Both causes and the independent pixel evidence are preserved in HANDOFF and logs.

**Raster sampling ruled 2026-10-15:** the owner accepts comparison C's smoother reduced grain,
"as long as it isnt cery bloaty or expensive for that difference". Replace full/window raster
transform sampling through one bounded shared implementation, remove the superseded path, and
measure native cost and memory before accepting it. This changes transformed raster paint only;
editable vector strokes retain their native renderer.

The shared raster replacement also exposes a pose mismatch: `LayerHostView.shownPose` updates live
strokes and fill previews but leaves `bakedImageView` unposed, while `PixelOps` poses the same stored
pixels. Align the backing through the existing origin-based pose, including its replacement hole;
verify translated, scaled and rotated backing against the composite before accepting the change.
When a stream composite displays the held edit instead of its layer host, its successful landing must
also certify that exact procedural tick; otherwise a normal lift waits for the next edit to settle.
Commit validation must use the vector's document-edit version: a live stream-frame arrival changes
its display version without changing the artwork and must not cancel the gesture.
Asynchronous base requests and derived images must carry immutable coverage of the edit they
rendered; a finite history of display versions can evict that identity before a delayed base lands.
Frozen previews must retain cached painted bounds for untouched elements.
Coverage review is also checking delayed derived-image landing across a cel switch: reject a picture
whose captured cel differs from the current host before assigning it or retiring pending previews.
For the same cel, distinguish an image stale relative to the model from one older than the image
already installed: the latter must not replace newer covered ink. Reuse the installed coverage value
for this ordering, rather than adding another history or cache.
Complete posed replacement pictures must reuse native element posing for ordinary vector ink;
posing its already-rasterized preview differs from committed re-stamping. Keep raster tiers on their
existing high-quality sampling, and preserve the deliberately unposed linked-ink behavior pinned by
`testAnInterpolatedCelDeclinesTheContainerPoseAndDoesNotKeyOnIt`. Core Graphics' high-quality sampling
also depends on full source extent, so an independently cropped pixel patch can differ at lift. A
virtual full-extent provider matches pixels but retains about 230 MiB of global resampling cache over
100 draws, even with released providers/contexts; that prototype is not accepted as a bounded preview.
`PixelOps.FrozenCel.pose` is the backing's container pose; ordinary native ink additionally has its
cel pose, while linked ink intentionally declines both. The shared replacement picture must carry
these placements independently, including the field's coordinate bridge, and remain correct if a
pose changes while its committed picture is still held.
The first bounded native-material renderer passes 25 of 26 focused tests, including exact exterior
pixels, stationary-boundary gradients and long patterned tails. Its 100-stroke fixture shares one
field and 144,000 evaluations, but temporary output image providers accumulate until the outer
autorelease pool and reach the 24 MiB guard near stroke 90. Retire each provider after its group is
drawn; keep the existing cap and shared coordinate cache. The corrected branch passes 26/26 methods,
with one field, 99 coordinate-cache hits and 11,535,208 peak counted bytes for 100 strokes. Final
integration gates remain. A separate bounded Lanczos prototype fixes full/window raster sampling
parity, but visibly changes grain under raster transforms. It stays external pending the owner's
appearance ruling; both preview and committed backing would need the same shared sampler.
The shown-space picture integration must also include the existing held derivation: its ordinary
ink is already posed, so placing it under the host pose applies that pose twice. A backing replacement
hole cannot be certified by an ink-only surface. Reuse the complete picture for this path too.
A pose-changing base may install only when it covers the newest complete pending picture; otherwise
an older base at the new pose would leave newer pending ink at the old pose. Derive that minimum from
the actual pending pictures and keep same-pose intermediate advances allowed.
At derived-image landing, a nil result from rendering is a failed picture, not an intentional clear.
Both synchronous and asynchronous render callers must preserve the previous image/key and pending
coverage on refusal; the explicit clear action remains separate. A failed image cannot certify an edit.
The strict material encoder can reject conflicting operation definitions. `ProjectStore.encodeJSON`
currently logs an encoding failure and omits that vector/recipe file, allowing staged validation to
accept an empty cel. Propagate any JSON encoding failure through the existing save tally so the
atomic package swap aborts; malformed material on load must likewise fail rather than become empty.
A failed JSON stage must also omit its final manifest. Otherwise moving it to Trash loses the
in-memory failure flag and later recovery could accept the omitted drawing as an empty cel. Reuse
the existing manifest-completeness check; no extra recovery marker or schema is needed.
Cutting a precise stroke also currently constructs its shown parent dab lattice with the default
quantized precision. Preserve the existing parent's precision (or the original stroke's precision
when first creating it), and verify a real cut/save roundtrip so Liquify's editable cuts do not lose
their retained geometry on reopen.

**Validation in progress (2026-10-14):** the first direct-displacement map folds under strong hard
and patterned brushes; actual raster pictures show stationary streaks and holes. Replace that map
with bounded reversible steps, shared by vector movement and raster resampling. A 4096² row sweep
expands a 2,126-byte saved gesture to about 7.7 MB of runtime field; evaluate one field across the
consumers and release it rather than retaining every gesture's field. Keep distant curved fill
segments unchanged when only a local part is deformed, and verify selection limits on linked frames.
Re-registration and motion-group splitting can replace group UUIDs: deformation captures must keep
their connection to the original source ink through stable source-cel/element occurrence identity,
including regrouping and cloned cels that share element UUIDs.
New ink drawn directly on an in-between must stay under the pen. The 60-digit source-coordinate
check shows why reversing old gestures is insufficient: a long patterned Push can map source
positions only 1e-15 pixels apart to destinations hundreds of pixels apart, beyond stored stroke
precision. Prior gestures therefore affect only local edits already named in their capture membership;
a newly drawn local edit uses the ordinary current-lattice storage path, and later gestures capture it
normally. Newly added source/subject ink still inherits a surviving or unambiguous group capture.
A realistic 100-pixel brush / 500-pixel drag needs 75.9 million field evaluations for a 67,100-pixel
window in the first reversible implementation; measure Release and reduce that work before accepting
interaction performance. Distant fill curves must retain their control points as well as their shape.
The existing source-block layer retarget and canvas-resize recipe mapping must carry the captured
deformation along, preserving its source identity and geometry rather than leaving stale coordinates.
An unreadable saved selection archive must fail current decoding, never become an unrestricted field.
Prepared native-tip sampling preserves every raster byte but still costs 13.592 seconds for the
84,956-pixel patterned window in isolated Release. Removing the production diagnostic pass yields
290,752,890 evaluations / 12.426 seconds and zero source-solve failures; this raster cost remains open.

The bounded continuous-flow experiment is complete: loose integration saves field evaluations but
changes the map; tighter integration loses the saving. Keep the current verified map
(evidence: `~/PaintWork/evidence/s49-liquify-flow-prototype/README.md`). An actual Release CPU sample
places 6,354 of 11,900 main-thread samples in the brush mask sampler. Exact lookup/SIMD experiments
did not show a reliable improvement and are not adopted. A safeguarded acceleration of the same
Euler inverse cuts the horizontal Push fixture to 179,020,536 evaluations (38.43% fewer), with all
339,824 rendered bytes unchanged and no failed source solves. Native Release validation now covers 18 signed/diagonal, grain, selection and other-mode fixtures:
all pixels match, no source solves fail, and non-Push coordinates/counts remain exact. The temporary
oracle is removed; restored Release 7/7 passed. Integrated into the feature branch as `ab99f9d`, `57d8247`; final combined
gates remain. Other modes retain ordinary iteration.
Evidence: `~/PaintWork/s49-liquify-profile/`, `~/PaintWork/evidence/s49-liquify-sampler/` and
`~/PaintWork/evidence/s49-liquify-inverse-acceleration/`. Raster interaction cost is still open.
The pending-lift finalizer now reuses finished procedural geometry and transfers the shown surface
through the existing held-picture lane; subsequent edits and snapshots join the one producer before
writing history. Focused logic/mutation and existing held-picture UI checks pass; feature-specific
cold-start checks and final integrated gates remain.

A local Push on a long patterned target stroke currently re-phases stamps beyond the moved region:
2,904 distant alpha pixels change in the measured Streaky fixture. Preserve the existing material
placement through the shared rest-walk/stamping seam; expanding the preview alone would merely show
the unintended distant change. Curved selection limits also require the same geometric boundary for
containment and the edge taper; the certified-curve correction is in focused validation.
**Vector selection edge ruled 2026-10-14:** *"B — Keep outside ink fixed."* The owner chose after seeing
the native comparison (48 shipped-spacing Streaky stamps: moving whole marks changes 1,703 exterior
alpha pixels; spatial deformation changes zero). Liquify must preserve every painted pixel outside
the selection while allowing texture to stretch inside, and vector strokes must remain editable.
Use spatial material deformation through the existing rest-walk/stamping seam; moving entire stamps
by their spine sites is rejected. The raster inverse kernel already fixes exterior pixels.
Evidence: `~/PaintWork/evidence/s49-liquify-selection-options-native-spacing/`.

- [ ] Liquify on raster and vector, including linked generated in-betweens, three modes, one undo step per stroke.

---

## (27) Stream the computer's screen as a layer

**Status** — briefed 2026-09-13, designed the same day ([STREAM.md](docs/STREAM.md)), and **built through
stage 4 the same day**: the Windows streamer (`streamer/`, installed on the laptop as the `PaintStreamer`
task), the iPad stream layer, the bar with Freeze / Bake Frame, files both ways. On the owner's iPad.
What remains is stage 5 — proving it on the real link with the owner at the laptop — and the one
device figure §5.3 asks for.

**The owner's brief, 2026-09-13, verbatim in the numbered points:**

1. *"The purpose of this feature is to be able to stream my windows computer's screen as a layer live
   on the app. The example use case is that the user will open up blender on their computer, then
   rotoscope a character, move the camera around in the computer, then continue rotoscoping, etc."*
2. *"This feature will require another app that is to be installed on my windows laptop which will
   stream the video to the Ipad."*
3. *"The windows app should also have a drop box for videos or images which when they are pasted into
   or uploaded, will appear on the app via the import video or image feature. If it is also possible,
   make the ipad app able to export to the windows app and save to the laptop."*
4. *"In the app, the stream tool should be under actions, and like a video it makes its own layer with
   the stream object inside of it."*
5. *"When the user is actively on the layer, there should be an options bar (the same kind as move or
   lasso tool), and in it should be the option to freeze the stream, or to bake the current frame. When
   the user presses bake to frame, the current frame in the layer is split as a new cel, and in that
   cel will be an image of the screen when it was baked. For example there are 4 frames and the stream
   layer has one cel stretching the 4 frames. The user is currently on cel 2. Once they hit bake, the
   cel will split into 3 cels: frame 1, frame 2, and frame 3 to 4. the cels in frame 1 and frame 3 to 4
   will not change. However, the cel in frame 2 will have the stream object replaced with an image
   object containing the snapshot of that frame."*
6. *"The paintapp streamer should be low latency and should not lag the main thread. Running it in a
   background thread might be smart, your decision. Note that for the most part, the computer side
   wont move."*
7. *"Just like a video layer, the user should be able to move the stream object in the layer using the
   move tool. The architecture for this is already well established."*
8. *"Note that the user may potentially use many screens or just want to stream a specific app."*
9. *"Note, this part is for the far future. I eventually intend to make the paint app compatible with
   windows, and thus there is the idea that instead of having a separate app, the paint app itself
   contains the streamer. This is a far off feature, but in case the two apps eventually merge, put
   some thought into the design of the architecture of the computer side streamer app. Better to plan
   ahead for potential future changes."*
10. *"There is the case the user may actively stream, then turn off their computer and continue on the
    app, then turn the computer back on and continue streaming."*
11. *"stream layers actively moving do not have to be rendered."*
12. *"The laptop that I want the streamer app in is not this mac but my windows computer. You should
    see it through tailscale."* — it is `desktop-cbr0fl6`, `100.104.85.111` on the tailnet; the iPad is
    `100.70.220.4`. SSH on the Windows box was **closed** on 2026-09-13 and needs the owner to enable
    OpenSSH Server before any Windows-side work can happen from this Mac.

**What is left** — STREAM.md §7 stage 5
- [ ] The owner streams Blender from the laptop to the iPad and rotoscopes over it; source switch,
      window close, laptop lock and reboot behave as STREAM.md §4.5 / §2.8 say.
- [ ] End-to-end latency MEASURED on the real link (a clock on the laptop screen beside the iPad);
      bitrate/GOP tuned if it needs it; numbers into PERFORMANCE.md.
- [ ] The redraw tick's cost MEASURED on the iPad (STREAM.md §8 names the outlet: the
      `ScreenStream` log line or the bar's `streamBar.tickSummary` marker).
- [ ] Owner-verified: Ctrl+V of a bitmap into the drop box (not exercisable over SSH).

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

## Later — the long-term features

**None of these are designed, and each needs its own conversation with the owner before it starts.**

- **(28) Audio.** Its stated blocker is **gone** — `PlaybackClock` is a drift-free wall-clock frame
  counter on the model, delivered by RENDER stage 1, which is exactly the hoist this item said it
  needed. `AVFoundation` is linked (for video), though no audio playback code exists.
- **(30) Video editor.** Its RENDER dependency is met — (29) shipped in full on 2026-09-06.
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
