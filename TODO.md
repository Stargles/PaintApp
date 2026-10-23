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

## Recent canvas freeze recordings — 2026-10-22

Owner: "you may want to check out the recent canvas freeze logs on the ipad if that helps you.
Not sure which version they got picked though, you figure that out." Read-only analysis is complete:
six October16–18 repair flights correlate to Releasef813346/app source840d68a, before Liquify and the
October22 recovery.346 deduplicated sequences include340 controls and6 repair hits, not6 proven
visible freezes. New Pencil/cancellation cases and healthy controls invalidate a universal late-third
fix. BUGS.md records findings and the next diagnostic seam; no speculative behavior change. Evidence:
`~/PaintWork/s50-freeze-logs/`. Remove this completed log-read request with the integration merge.

## (178) Liquify tool

**Current status — 2026-10-22.** The shipped app is recovered: main Release source `17b438c`, app source `840d68a`; its signature and embedded profile verify, and the owner confirmed it opens. Renewal repair `5e93bf0` shares clean/build settings, fails closed on clean errors, verifies the app seal and requires five days of profile life. The profile expires 2026-10-30. Evidence: [auto-resign report](docs/bug-evidence/auto-resign-2026-10-22.md) and `~/PaintWork/s50-recovery/`.

Liquify remains unmerged and is not on the iPad. Integration branch `tmp/s49-integration` consolidates the old sole-consumer presenter with the Liquify procedure at `c78aac8`; focused Debug compilation and all 25 lifecycle/raster checks passed, zero failures/skips. This cleanup removes the generic wrapper and adds no renderer or cache. The spatial material renderer remains integrated through VectorCanvas, with tile-scoped work. Keep useful feature-scoped state where it serves the workflow, with existing synchronization, cancellation and single-producer behavior. The unchanged linked Release workflow now passes1/1: reshape, exact cold-reopened picture and edited-source following. Root inspected four pictures and preserved41 Documents files with hashes; the linked recipe contains its saved deformation. The earlier Debug15s timeout remains recorded; its temporary diagnostic is restored, and gesture/predicate/timeout are unchanged.

The verified census is 5282 fast tests across 256 selected classes and 5864 full tests, excluding three private static helpers. Quiet Release cost passed2/2 at source `7e780d7`: all8 producer pictures match exactly, all18 inverse fixtures retain native hashes/counts; production medians are19.1%/23.3% of scalar hard/pattern cost. Retain batching. PERFORMANCE records simulator scope; this is no device-latency claim. Still open: final fast Debug/Release, one full suite in shipped Release configuration, sampler C physical first-use cost and physical iPad qualification. Simulator test seeds are enabled in Release; full-suite configuration is not mandated by repository rules. The five-method device patch and native cold/warm benchmark are prepared but not compiled or run; get fresh saved/unlocked device readiness before physical work. Evidence is indexed in `HANDOFF.md` and `~/PaintWork/s49-liquify-logs/`.

All8 feature UI methods now pass in Release across linked1, raster/vector6 and native9 controls1
runs, zero failures/skips. Root inspected reshape/cold-reopen pictures and the settled iPad9 controls
photo: Size/Power, brush and all3 modes fit. The raster cold test's unasserted trailing rotation,
layer-panel toggles and invalid midflight photo are removed at `0cabd6c`; its valid portrait reopen
capture and every existing assertion remain. Final gates are next. Keep one-shot repairs until the owner confirms real
scenes after installation.

Final Debug fast attempt stopped partially at1430 tests (1427 passed, one real failure, one cancelled
test, one skip); it is not a qualified fast tier. The identity fixture repair `621c15d` retains fitted
lattices and all original assertions/cases; focused baseline/restored2/2 and a fault causing exactly
the two group/spacing identity failures are verified. Production guard unchanged/file restored
byte-exact. Rerun the whole final gates; let each configuration finish before stopping on failures.
The complete second Debug attempt is running and exposed one further malformed identity fixture:
FrameBakeKeyLogicTests' derived-acquisition row has zero source references. After this configuration
finishes, give that row two existing resolvable cels, keep all25 rows/assertions unchanged, and prove
that omitting the derived identity from the digest reproduces the intended acquired/retimed collision.
The bounded related-fixture scan found no further positive identity cases needing this correction.

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

**Raster sampling ruled 2026-10-15:** the owner accepts comparison C's smoother reduced grain,
"as long as it isnt cery bloaty or expensive for that difference". The shared bounded sampler is
implemented; its physical first-use cost remains open. Transformed raster paint uses it, while editable
vector strokes retain their native renderer.

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
- **Interpolation overhaul.** Owner, 2026-10-22: "Interpolation will probably be overhauled sometime
  soon so it works better. I'll let you know in the future." Await that design conversation; do not
  research or implement an overhaul now.
---

## Carried — deliberate, and not an ask

- **The raster Move's undo half.** `finalizePendingGesturesForHistoryAction` has fill, shape and text
  arms and no raster-float arm.
- **Freeform text's minimum-size exemption** is still unruled.
