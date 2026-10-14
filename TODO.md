# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what *we* find.

**Session 49 (2026-10-14):** the owner asked to continue through every actionable item, stopping only
for genuinely required input or context degradation. Agent count is unrestricted for now; usage
conservation and output quality take priority over speed. Use focused delegation and cheaper models
for routine work, with occasional queue reports. The owner is asleep until 10 a.m. Toronto time;
continue independently and defer further questions until then.

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

## (179) Everything live previews at the rate the device can draw, and writes the scene once

**Status** — asked 2026-10-12; extends (173)'s held-edit mechanism (`CanvasManager.liveElementEdit`,
`ElementEditSession`, `WindowSurfaceView`) to every control that still writes the document per tick.
The assessment's commits 1–6 are merged: `LatestWins`; the live pair, onion skin and eyedropper on it;
one held slot, `CanvasManager.liveEdit`; the effect parameter sliders, held, with the whole frame
composited from the held grade (PERFORMANCE.md §30); the owner's half-detail ruling (below; RENDER.md
§2.12, §30.4: 4096² now previews every tick); the whole-effect editors, the Duplicate Offset's box and a
grade's graph-band drags (commit 5); and layer and folder Opacity, a value layer's colour and the
transform modes' Rotate, Shake and Parallax sliders (commit 6, §30.5); and commit 8 — a smart shape's ink
drawn off the main thread into a surface, the text recipe on its own object (`TextSettings`) with the box's
glyphs laid out off the main thread, and the text box's drags and a lifted bitmap's Move box ticking the
canvas instead of the editor (PERFORMANCE §32); commit 9 — an in-between's Timing slider, a guide's handle
and a spacing dot held, with the in-between drawn by its host off the main thread (§33.2); the brush colour on
an object of its own (`BrushColorState`, §33.1: 11.6 → 7.1 ms a tick, no editor pass); and a graph-band drag
of a target's channels or an animation group's pose held (§33.3 — a marquee across kinds of channel still
writes per tick); and commit 10 — the fill's renders through a `LatestWins` and its picture drawn into a
surface off the main thread (§34.1). Commit 7 (mask tuning live) moved to (35). The scrub's decode and the
onion skin's surface were measured and not needed (§34.2). **Every box below but the device measurement
is done**: the iPad run of `PlaybackProbe` is owed.

**Ruled 2026-10-12, on §30**: *lower detail only on big scenes* — above about 4 million pixels (twice the
owner's usual 2048×1024) a drag preview is drawn at half detail while the finger is down and full detail
at the lift; at or below it, full detail. This is a drag-only exception to RENDER.md §2.12 ("the knob is
the truth"), made by the owner; the threshold is one named constant (`DragPreviewDetail`).

The owner, asked whether the remaining per-tick sliders (layer Opacity, effect parameters, mask tuning,
the text panel) should get (173)'s fix: *"for all of them, cant there be a system where it just slows
down the redrawing dynamically to not lag the main thread or crash, so that the user gets near live
feedback? if so then implement it."*

And, the same day: *"I feel like the throttle system should apply universally in the app for things that
require live reupdating. See if the implmentation would not be too complex or big, and if so then
implement it."* — so the scope is every live re-update (drags, sliders, scrubs, streams, previews), and
the existing per-feature coalescers are folded into the one seam rather than kept beside it.

So: one mechanism for every live control — the value is held off the document for the gesture and
committed once at the lift as one undo step, and the preview redraws **latest-value-wins with one render
in flight**, so its rate falls to what the device can draw and memory stays flat (PERFORMANCE.md §29 is
why: pictures handed to Core Animation faster than the render server frees them).

- [x] Assessment first: every live re-update path and every existing throttle/coalescer, the one seam,
      and its size. Built if it is one clean seam; brought to the owner if it means a renderer rewrite.
- [x] Inventory every control that writes the document per tick (incl. HANDOFF's "ruled to wait" grade
      sliders, grade graph nodes and the Duplicate Offset box, which this ruling supersedes).
- [x] One held-value + latest-wins preview seam they all use; no per-control copies — commits 1–6 and 8–10
      merged (`1a715ec`..`0f09447`, `bd5ffec`, `f6586c9`, commits 6, 8, 9 and 10), and the graph-band
      channel drags; 7 is (35)'s.
- [x] Half-detail drag preview above the size threshold (PERFORMANCE.md §30.4).
- [x] The brush colour panel's tick: its own small publisher (`BrushColorState`) — the toolbar swatches and
      the canvas follow per tick, the editor does not re-evaluate (PERFORMANCE §33.1).
- [ ] Measured with `PlaybackProbe` before/after, as §29 was — on the iPad 9 simulator: the effect slider
      (PERFORMANCE.md §30), half detail (§30.4), the Opacity slider (§30.5), a smart shape's handle drag
      (§32), the brush colour (§33.1) and the fill slider (§34.1). **Owed: the iPad itself** — the probe's
      `effect`, `opacity`, `shape` and `fill` modes on the owner's device. Owner saved the scene and
      unlocked it 2026-10-14. Installed `7cf3245` supports only the effect baseline; the other three
      modes need an updated build (unknown modes in that build silently run playback).

## (177) A stream layer can draw in place in the layer stack

**Status** — asked 2026-10-12.

*"currently the stream layer renders on top of everything. It would be nice if the stream layer still
followed the layer heigharchy. I'm pretty sure this measure was to prevent re-rendering every time the
stream moves, but I feel like it is okay as long as we add a switch to the stream options menu where you
can flip it from rendering on top or in place."*

**What the survey found**: the stream is already in layer order while every layer above it is plain; it
goes on top only when a layer above blends, masks, grades or is a Guide (`LivePairCut.overHost`). In
place means re-compositing the layers above the stream every stream tick, in a window — one more consumer
of (179)'s scheduler, so this follows (179). Decided 2026-10-12 (the orchestrator; the owner may
overrule): the switch is stored **per stream**, beside Freeze (`StreamRef`), and defaults to **on top**.

- [ ] A switch in the stream bar: on top (today) / in place.

**In flight, session 49** — per-stream viewing state; display-only window recipe with the live stroke
entered at its layer before grading, masks and blends. The newest request scheduler and reusable
surfaces bound the queue; saved packages receive a one-shot strict-format repair. Bake/export remain
reference-free. Implementation: `tmp/s49-stream`.

## (35) Advanced masks — colour masks beside the alpha mask

**Status** — promoted from "Later" 2026-10-12; the owner will describe what it is meant to be once told
what is already recorded.

The original ask (2026-09-01): *"right now we have alpha masks. I like the idea of more advanced masks.
This includes the ability to mask specific sets of colours (with a deviation threshold range), and a new
special blend mode called colour reassign, where you can select colours and reassign them to other
colours of your choosing (you can recolour your drawings)."*

2026-10-12: *"The idea I sort of have is that it is sort of like the recolour, where you can set specific
colors as the mask. The previous alpha mask feature should also still be present. This probably will
have a lot of overlapping code with that feature, so follow good architecture protocols."*

**What is already built**: the colour-reassign half shipped as the Recolour effect (`Effect.recolor`,
TODO (60)), so the colour mask is what is owed.

**Ruled 2026-10-12**: the colour mask looks for the chosen colours **on the ticked layers**, exactly as
today's alpha mask reads their ink. Proposed and not objected to: one mask, not a second kind —
`AlphaMask` gains an optional colour list (Recolour's colour key, tolerance and eyedropper picking,
shared rather than copied); with no colours picked it is today's alpha mask, and picking colours narrows
it to those colours. The survey is `~/PaintWork/design/s48-survey-masks-stream-liquify.md` §A (four
colour-distance definitions exist; the mask uses Recolour's; per-pixel Oklab wants memoising per value).

- [ ] Mask tuning (threshold, antialias) becomes **per mask** — the owner on 2026-10-12 — replacing
      `MaskResolver`'s process-wide statics — and its sliders preview live through (179)'s held slot and
      lane F (the assessment's commit 7, moved here so the per-mask value is what is held).
- [ ] Built on the existing mask and recolour modules rather than beside them.
- [ ] After (179), which touches mask tuning's per-tick path.

## (178) Liquify tool

**Status** — asked 2026-10-12.

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

**Ruled 2026-10-01: keep the limitation** — a stream layer under a blend mode or effect is not live
(46–73 ms a tick); the bar says so. Opacity is fine.

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
